//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.ast_info;

import dparse.lexer;
import dparse.ast;

enum BraceIndentInfoFlags
{
    tempIndent = 1 << 0,
}

struct BraceIndentInfo
{
    size_t startLocation;
    size_t endLocation;

    uint flags;

    uint beginIndentLevel;
}

struct StructInitializerInfo
{
    size_t startLocation;
    size_t endLocation;
}

/// AST information that is needed by the formatter.
struct ASTInformation
{
    /// Sorts the arrays so that binary search will work on them
    void cleanup()
    {
        import std.algorithm : sort, uniq;
        import std.array : array;

        sort(doubleNewlineLocations);
        sort(spaceAfterLocations);
        sort(unaryLocations);
        sort(attributeDeclarationLines);
        sort(atAttributeStartLocations);
        sort(caseEndLocations);
        sort(structInitStartLocations);
        sort(structInitEndLocations);
        sort(funLitStartLocations);
        sort(funLitEndLocations);
        sort(conditionalWithElseLocations);
        sort(conditionalStatementLocations);
        sort(arrayStartLocations);
        sort(assocArrayStartLocations);
        sort(contractLocations);
        sort(constraintLocations);
        sort(constructorDestructorLocations);
        sort(staticConstructorDestructorLocations);
        sort(sharedStaticConstructorDestructorLocations);
        sort!((a,b) => a.endLocation < b.endLocation)
            (indentInfoSortedByEndLocation);
        sort!((a,b) => a.endLocation < b.endLocation)
            (structInfoSortedByEndLocation);
        sort(ufcsHintLocations);
        ufcsHintLocations = ufcsHintLocations.uniq().array();
        sort(ternaryColonLocations);
        sort(namedArgumentColonLocations);
    }

    /// Locations of end braces for struct bodies
    size_t[] doubleNewlineLocations;

    /// Locations of tokens where a space is needed (such as the '*' in a type)
    size_t[] spaceAfterLocations;

    /// Locations of unary operators
    size_t[] unaryLocations;

    /// Lines containing attribute declarations
    size_t[] attributeDeclarationLines;

    /// Lines containing attribute declarations that can be followed by a new line
    size_t[] atAttributeStartLocations;

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

    /// Locations of aggregate bodies (struct, class, union)
    size_t[] aggregateBodyLocations;

    /// Locations of function bodies
    size_t[] funBodyLocations;

    /// Conditional statements that have matching "else" statements
    size_t[] conditionalWithElseLocations;

    /// Conditional statement locations
    size_t[] conditionalStatementLocations;

    /// Locations of start locations of array initializers
    size_t[] arrayStartLocations;

    /// Locations of start locations of associative array initializers
    size_t[] assocArrayStartLocations;

    /// Locations of "in" and "out" tokens that begin contracts
    size_t[] contractLocations;

    /// Locations of template constraint "if" tokens
    size_t[] constraintLocations;

    /// Locations of constructor/destructor "shared" tokens ?
    size_t[] sharedStaticConstructorDestructorLocations;

    /// Locations of constructor/destructor "static" tokens ?
    size_t[] staticConstructorDestructorLocations;

    /// Locations of constructor/destructor "this" tokens ?
    size_t[] constructorDestructorLocations;

    /// Locations of '.' characters that might be UFCS chains.
    size_t[] ufcsHintLocations;

    BraceIndentInfo[] indentInfoSortedByEndLocation;

    /// Opening & closing braces of struct initializers
    StructInitializerInfo[] structInfoSortedByEndLocation;

    /// Locations ternary expression colons.
    size_t[] ternaryColonLocations;

    /// Locations of named arguments of function call or struct constructor.
    size_t[] namedArgumentColonLocations;
}

/// Collects information from the AST that is useful for the formatter
final class FormatVisitor : ASTVisitor
{
    alias visit = ASTVisitor.visit;

    /**
     * Params:
     *     astInformation = the AST information that will be filled in
     */
    this(ASTInformation* astInformation)
    {
        this.astInformation = astInformation;
    }

    override void visit(const ArrayInitializer arrayInitializer)
    {
        astInformation.arrayStartLocations ~= arrayInitializer.startLocation;
        arrayInitializer.accept(this);
    }

    override void visit(const ArrayLiteral arrayLiteral)
    {
        astInformation.arrayStartLocations ~= arrayLiteral.tokens[0].index;
        arrayLiteral.accept(this);
    }

    override void visit(const AssocArrayLiteral assocArrayLiteral)
    {
        astInformation.arrayStartLocations ~= assocArrayLiteral.tokens[0].index;
        astInformation.assocArrayStartLocations ~= assocArrayLiteral.tokens[0].index;
        assocArrayLiteral.accept(this);
    }

    override void visit (const SharedStaticConstructor sharedStaticConstructor)
    {
        astInformation.sharedStaticConstructorDestructorLocations ~= sharedStaticConstructor.location;
        sharedStaticConstructor.accept(this);
    }

    override void visit (const SharedStaticDestructor sharedStaticDestructor)
    {
        astInformation.sharedStaticConstructorDestructorLocations ~= sharedStaticDestructor.location;
        sharedStaticDestructor.accept(this);
    }

    override void visit (const StaticConstructor staticConstructor)
    {
        astInformation.staticConstructorDestructorLocations ~= staticConstructor.location;
        staticConstructor.accept(this);
    }

    override void visit (const StaticDestructor staticDestructor)
    {
        astInformation.staticConstructorDestructorLocations ~= staticDestructor.location;
        staticDestructor.accept(this);
    }

    override void visit (const Constructor constructor)
    {
        astInformation.constructorDestructorLocations ~= constructor.location;
        constructor.accept(this);
    }

    override void visit (const Destructor destructor)
    {
        astInformation.constructorDestructorLocations ~= destructor.index;
        destructor.accept(this);
    }

    override void visit (const FunctionBody functionBody)
    {
        if (auto bd = functionBody.specifiedFunctionBody)
        {
            if (bd.blockStatement)
            {
                astInformation.funBodyLocations ~= bd.blockStatement.startLocation;
            }
        }
        functionBody.accept(this);
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
        if (funcLit.specifiedFunctionBody !is null)
        {
            const bs = funcLit.specifiedFunctionBody.blockStatement;

            astInformation.funLitStartLocations ~= bs.startLocation;
            astInformation.funLitEndLocations ~= bs.endLocation;
            astInformation.indentInfoSortedByEndLocation ~=
                BraceIndentInfo(bs.startLocation, bs.endLocation);
        }
        funcLit.accept(this);
    }

    override void visit(const DefaultStatement defaultStatement)
    {
        astInformation.caseEndLocations ~= defaultStatement.colonLocation;
        defaultStatement.accept(this);
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

    override void visit(const SpecifiedFunctionBody specifiedFunctionBody)
    {
        if (specifiedFunctionBody.blockStatement !is null)
            astInformation.doubleNewlineLocations ~= specifiedFunctionBody.blockStatement.endLocation;
        specifiedFunctionBody.accept(this);
    }

    override void visit(const StructInitializer structInitializer)
    {
        astInformation.structInitStartLocations ~= structInitializer.startLocation;
        astInformation.structInitEndLocations ~= structInitializer.endLocation;
        astInformation.structInfoSortedByEndLocation ~=
            StructInitializerInfo(structInitializer.startLocation, structInitializer.endLocation);
        astInformation.indentInfoSortedByEndLocation ~=
            BraceIndentInfo(structInitializer.startLocation, structInitializer.endLocation);

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
        if (invariant_.blockStatement !is null)
            astInformation.doubleNewlineLocations ~= invariant_.blockStatement.endLocation;
        
        invariant_.accept(this);
    }

    override void visit(const StructBody structBody)
    {
        astInformation.aggregateBodyLocations ~= structBody.startLocation;
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
        import std.typecons : rebindable;

        int chainLength;
        auto u = rebindable(unary);
        while (u !is null)
        {
            if (u.identifierOrTemplateInstance !is null
                    && u.identifierOrTemplateInstance.templateInstance !is null)
                chainLength++;
            u = u.unaryExpression;
        }
        if (chainLength > 1)
        {
            u = unary;
            while (u.unaryExpression !is null)
            {
                astInformation.ufcsHintLocations ~= u.dotLocation;
                u = u.unaryExpression;
            }
        }
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

    override void visit(const FunctionAttribute functionAttribute)
    {
        if (functionAttribute.atAttribute !is null)
            astInformation.atAttributeStartLocations ~= functionAttribute.atAttribute.startLocation;
        functionAttribute.accept(this);
    }

    override void visit(const MemberFunctionAttribute memberFunctionAttribute)
    {
        if (memberFunctionAttribute.atAttribute !is null)
            astInformation.atAttributeStartLocations ~= memberFunctionAttribute.atAttribute.startLocation;
        memberFunctionAttribute.accept(this);
    }

    override void visit(const Attribute attribute)
    {
        if (attribute.atAttribute !is null)
            astInformation.atAttributeStartLocations ~= attribute.atAttribute.startLocation;
        attribute.accept(this);
    }

    override void visit(const StorageClass storageClass)
    {
        if (storageClass.atAttribute !is null)
            astInformation.atAttributeStartLocations ~= storageClass.atAttribute.startLocation;
        storageClass.accept(this);
    }

    override void visit(const InContractExpression inContractExpression)
    {
        astInformation.contractLocations ~= inContractExpression.inTokenLocation;
        inContractExpression.accept(this);
    }

    override void visit(const InStatement inStatement)
    {
        astInformation.contractLocations ~= inStatement.inTokenLocation;
        inStatement.accept(this);
    }

    override void visit(const OutContractExpression outContractExpression)
    {
        astInformation.contractLocations ~= outContractExpression.outTokenLocation;
        outContractExpression.accept(this);
    }

    override void visit(const OutStatement outStatement)
    {
        astInformation.contractLocations ~= outStatement.outTokenLocation;
        outStatement.accept(this);
    }

    override void visit(const TernaryExpression ternaryExpression)
    {
        astInformation.ternaryColonLocations ~= ternaryExpression.colon.index;
        ternaryExpression.accept(this);
    }

    override void visit(const FunctionCallExpression functionCall)
    {
        // Check if function has any arguments.
        if (functionCall.arguments.namedArgumentList is null)
        {
            functionCall.accept(this);
            return;
        }

        /+
        Items are function arguments: f(<item>, <item>);
        Iterate them and check if they are named arguments: tok!":" belongs to a
        named argument if it is preceeded by one tok!"identifier" (+ any number
        of comments):
        +/
        foreach (item; functionCall.arguments.namedArgumentList.items)
        {
            // Set to true after first tok!"identifier".
            auto foundIdentifier = false;

            foreach (t; item.tokens)
            {
                if (t.type == tok!"identifier" && !foundIdentifier)
                {
                    foundIdentifier = true;
                    continue;
                }

                if (t.type == tok!":" && foundIdentifier)
                {
                    astInformation.namedArgumentColonLocations ~= t.index;
                }

                break;
            }
        }

        functionCall.accept(this);
    }

private:
    ASTInformation* astInformation;
}
