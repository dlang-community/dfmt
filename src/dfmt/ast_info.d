//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.ast_info;

import dparse.lexer;
import dparse.ast;

struct Import
{
    string[] importStrings;
    string renamedAs;
	string attribString;
}

/// AST information that is needed by the formatter.
struct ASTInformation
{
    struct LocationRange
    {
        size_t startLocation;
        size_t endLocation;
    }

    /// Sorts the arrays so that binary search will work on them
    void cleanup()
    {
        finished = true;

        import std.algorithm : sort;

        sort(doubleNewlineLocations);
        sort(spaceAfterLocations);
        sort(unaryLocations);
        sort(attributeDeclarationLines);
        sort(caseEndLocations);
        sort(structInitStartLocations);
        sort(structInitEndLocations);
        sort(funLitStartLocations);
        sort(funLitEndLocations);
        sort(conditionalWithElseLocations);
        sort(conditionalStatementLocations);
        sort(arrayStartLocations);
        sort(contractLocations);
        sort(constraintLocations);
        sort(skipTokenLocations);

    }

    /// Locations of end braces for struct bodies
    size_t[] doubleNewlineLocations;

    /// Locations of tokens where a space is needed (such as the '*' in a type)
    size_t[] spaceAfterLocations;

    /// Location-Ranges where scopes begin and end
    LocationRange[] scopeLocationRanges;

    /// zero is module scope
    size_t scopeOrdinalOfLocation(const size_t location) const
    {
        size_t bestOrdinal = 0;

        LocationRange bestRange = scopeLocationRanges[bestOrdinal];

        foreach (i; 1 .. scopeLocationRanges.length)
        {
            LocationRange nextRange = scopeLocationRanges[i];

            if (nextRange.startLocation > location)
                break;

            if (nextRange.endLocation > location)
            {
                bestRange = nextRange;
                bestOrdinal = i;
            }

        }

        return bestOrdinal;
    }

    bool importStringLess(const Import a, const Import b) const
    {
        bool result;
        result = a.importStrings < b.importStrings;
        /*
        if (moduleNameStrings.length && isCloserTo(a.importStrings, b.importStrings, moduleNameStrings)
        {
            
        }
        */

        return result;
    }

    static struct ImportLine
    {
        string importString;
        string attribString;
        string renamedAs;
    }

    /// returns an array of indecies into the token array
    /// which are the indecies of the imports to be written
    /// in sorted order
    /// newlines for grouping are enoded as a null entry
    ImportLine[] importLinesFor(const size_t scopeOrdinal) const
    {
        import std.algorithm;
        import std.range;

        uint idx = 0;
        ImportLine[] result;

        auto imports = importScopes[scopeOrdinal];

        if (imports.length)
        {
            const max_sorted_imports_length = imports.length * 2;
            // account for newlines
            result.length = max_sorted_imports_length;
            auto sortedImports =
                (cast(Import[])imports).sort!((a, b) => importStringLess(a, b))
                .release;

            foreach(i, imp;sortedImports)
            {
                if (i > 0)
                {
                    const prev = sortedImports[i-1];
                    if (prev.importStrings.length < 2
                        || imp.importStrings[0 .. $-1] != prev.importStrings[0 .. $-1]
                    )
                    {
                        result[idx++].importString = null;
                    }
                }

                result[idx].importString = imp.importStrings.join(".");
                result[idx].renamedAs = imp.renamedAs;
                result[idx].attribString = imp.attribString;
                idx++;
            }

            result = result[0 .. idx];
        }
        else
        {
            result = null;
        }

        return result;
    }

    /// Locations of unary operators
    size_t[] unaryLocations;

    /// Locations of tokens to be skipped
    size_t[] skipTokenLocations;

    /// Lines containing attribute declarations
    size_t[] attributeDeclarationLines;

    /// lines in which imports end
    size_t[] importEndLines;

    /// Case statement colon locations
    size_t[] caseEndLocations;

    /// Opening braces of struct initializers
    size_t[] structInitStartLocations;

    /// Closing braces of struct initializers
    size_t[] structInitEndLocations;

    /// Opening braces of function literals
    size_t[] funLitStartLocations;

    /// Closing braces of function literals
    size_t[] funLitEndLocations;

    /// Conditional statements that have matching "else" statements
    size_t[] conditionalWithElseLocations;

    /// Conditional statement locations
    size_t[] conditionalStatementLocations;

    /// Locations of start locations of array initializers
    size_t[] arrayStartLocations;

    /// Locations of "in" and "out" tokens that begin contracts
    size_t[] contractLocations;

    /// Locations of template constraint "if" tokens
    size_t[] constraintLocations;

    /// cleanup run;
    bool finished;

    /// contains all imports inside scope
    Import[][] importScopes;

    ///contain the current fqn of the module
    string[] moduleNameStrings;
}

/// Collects information from the AST that is useful for the formatter
final class FormatVisitor : ASTVisitor
{
    /**
     * Params:
     *     astInformation = the AST information that will be filled in
     */

    this(ASTInformation* astInformation)
    {
        this.astInformation = astInformation;
        if (this.astInformation.scopeLocationRanges.length != 0)
            assert(0, "astinformation seems to be dirty");

        this.astInformation.scopeLocationRanges ~= ASTInformation.LocationRange(0, size_t.max);
        this.astInformation.importScopes.length = 1;
    }

    void addScope(const size_t startLocation, const size_t endLocation)
    {
        astInformation.scopeLocationRanges ~= ASTInformation.LocationRange(startLocation,
                endLocation);
        astInformation.importScopes.length += 1;
    }

    override void visit(const ArrayInitializer arrayInitializer)
    {
        astInformation.arrayStartLocations ~= arrayInitializer.startLocation;
        arrayInitializer.accept(this);
    }
 
    void addImport(size_t scopeId, string[] importString, string renamedAs, string importAttribString)
    {
        import std.stdio;

        writeln("addImport(", scopeId, ", ", importString, ", ",  renamedAs, ", ", importAttribString, ")");

        astInformation.importScopes[scopeId] ~= Import(importString, renamedAs, importAttribString);
    }

    override void visit(const SingleImport singleImport)
    {
        auto scopeOrdinal = size_t.max;

        if (singleImport.identifierChain)
        {
            string[] importString;
            string renamedAs = null;

            auto ic = singleImport.identifierChain;
            foreach (ident; ic.identifiers)
            {
                importString ~= ident.text;
            }

            scopeOrdinal = astInformation.scopeOrdinalOfLocation(ic.identifiers[0].index);

            if (singleImport.rename.text && singleImport.rename.text.length)
                renamedAs = singleImport.rename.text;

            addImport(scopeOrdinal, importString, renamedAs, importAttribString);

        }
        else
        {
            assert (0, "singleImport without identifierChain");
        }


    }

    override void visit(const ConditionalDeclaration dec)
    {
        if (dec.hasElse)
        {
            auto condition = dec.compileCondition;
            if (condition.versionCondition !is null)
            {
                astInformation.conditionalWithElseLocations
                    ~= condition.versionCondition.versionIndex;
            }
            else if (condition.debugCondition !is null)
            {
                astInformation.conditionalWithElseLocations ~= condition.debugCondition.debugIndex;
            }
            // Skip "static if" because the formatting for normal "if" handles
            // it properly
        }
        dec.accept(this);
    }

    override void visit(const Constraint constraint)
    {
        astInformation.constraintLocations ~= constraint.location;
        constraint.accept(this);
    }

    override void visit(const ConditionalStatement statement)
    {
        auto condition = statement.compileCondition;
        if (condition.versionCondition !is null)
        {
            astInformation.conditionalStatementLocations ~= condition.versionCondition.versionIndex;
        }
        else if (condition.debugCondition !is null)
        {
            astInformation.conditionalStatementLocations ~= condition.debugCondition.debugIndex;
        }
        statement.accept(this);
    }

    override void visit(const FunctionLiteralExpression funcLit)
    {
        if (funcLit.functionBody !is null)
        {
            astInformation.funLitStartLocations ~= funcLit.functionBody
                .blockStatement.startLocation;
            astInformation.funLitEndLocations ~= funcLit.functionBody.blockStatement.endLocation;
        }
        funcLit.accept(this);
    }

    override void visit(const DefaultStatement defaultStatement)
    {
        astInformation.caseEndLocations ~= defaultStatement.colonLocation;
        defaultStatement.accept(this);
    }

    /// this is the very limited usecase of printing attribs which may be
    /// attached to imports (therefore it's not compleate at all)
    /// HACK this method also adds the original token to the ignore_tokens

    private string toImportAttribString (const (Attribute)[] attributes)
    {
        string result;

        foreach(attrib;attributes)
        {

            if (attrib.attribute.type == tok!"public")
            {
                result ~= "public ";
                astInformation.skipTokenLocations ~= attrib.attribute.index;
            }
            else if (attrib.attribute.type == tok!"private")
            {
                result ~= "private ";
                astInformation.skipTokenLocations ~= attrib.attribute.index;
            }
            else if (attrib.attribute.type == tok!"static")
            {
                result ~= "static ";
                astInformation.skipTokenLocations ~= attrib.attribute.index;
            }
        }

        return result;
    }

    override void visit(const Declaration declaration)
    {
        if (declaration.importDeclaration)
        {
            importAttribString = toImportAttribString(declaration.attributes);
        }

        declaration.accept(this);

        importAttribString = null;
    }

    override void visit(const CaseStatement caseStatement)
    {
        astInformation.caseEndLocations ~= caseStatement.colonLocation;
        caseStatement.accept(this);
    }

    override void visit(const CaseRangeStatement caseRangeStatement)
    {
        astInformation.caseEndLocations ~= caseRangeStatement.colonLocation;
        caseRangeStatement.accept(this);
    }

    override void visit(const FunctionBody functionBody)
    {
        if (functionBody.blockStatement !is null)
        {
            auto bs = functionBody.blockStatement;

            addScope(bs.startLocation, bs.endLocation);
            astInformation.doubleNewlineLocations ~= bs.endLocation;
        }

        if (functionBody.bodyStatement !is null && functionBody.bodyStatement
                .blockStatement !is null)
        {
            auto bs = functionBody.bodyStatement.blockStatement;

            addScope(bs.startLocation, bs.endLocation);
            astInformation.doubleNewlineLocations ~= bs.endLocation;
        }

        functionBody.accept(this);
    }

    override void visit(const StructInitializer structInitializer)
    {
        astInformation.structInitStartLocations ~= structInitializer.startLocation;
        astInformation.structInitEndLocations ~= structInitializer.endLocation;
        structInitializer.accept(this);
    }

    override void visit(const EnumBody enumBody)
    {
        astInformation.doubleNewlineLocations ~= enumBody.endLocation;
        enumBody.accept(this);
    }

    override void visit(const Unittest unittest_)
    {
        astInformation.doubleNewlineLocations ~= unittest_.blockStatement.endLocation;
        unittest_.accept(this);
    }

    override void visit(const Invariant invariant_)
    {
        astInformation.doubleNewlineLocations ~= invariant_.blockStatement.endLocation;
        invariant_.accept(this);
    }

    override void visit(const StructBody structBody)
    {
        addScope(structBody.startLocation, structBody.endLocation);
        astInformation.doubleNewlineLocations ~= structBody.endLocation;
        structBody.accept(this);
    }

    override void visit(const TemplateDeclaration templateDeclaration)
    {
        astInformation.doubleNewlineLocations ~= templateDeclaration.endLocation;
        templateDeclaration.accept(this);
    }

    override void visit(const TypeSuffix typeSuffix)
    {
        if (typeSuffix.star.type != tok!"")
            astInformation.spaceAfterLocations ~= typeSuffix.star.index;
        typeSuffix.accept(this);
    }

    override void visit(const UnaryExpression unary)
    {
        if (unary.prefix.type == tok!"~" || unary.prefix.type == tok!"&"
                || unary.prefix.type == tok!"*"
                || unary.prefix.type == tok!"+" || unary.prefix.type == tok!"-")
        {
            astInformation.unaryLocations ~= unary.prefix.index;
        }
        unary.accept(this);
    }

    override void visit(const AttributeDeclaration attributeDeclaration)
    {
        astInformation.attributeDeclarationLines ~= attributeDeclaration.line;
        attributeDeclaration.accept(this);
    }

    override void visit(const InStatement inStatement)
    {
        astInformation.contractLocations ~= inStatement.inTokenLocation;
        inStatement.accept(this);
    }

    override void visit(const OutStatement outStatement)
    {
        astInformation.contractLocations ~= outStatement.outTokenLocation;
        outStatement.accept(this);
    }

private:
    ASTInformation* astInformation;
    string importAttribString;

    alias visit = ASTVisitor.visit;
}
