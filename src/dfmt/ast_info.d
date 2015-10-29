//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.ast_info;

import dparse.lexer;
import dparse.ast;

/// AST information that is needed by the formatter.
struct ASTInformation
{
    /// Sorts the arrays so that binary search will work on them
    void cleanup()
    {
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
    }

    /// Locations of end braces for struct bodies
    size_t[] doubleNewlineLocations;

    /// Locations of tokens where a space is needed (such as the '*' in a type)
    size_t[] spaceAfterLocations;

    /// Locations of unary operators
    size_t[] unaryLocations;

    /// Lines containing attribute declarations
    size_t[] attributeDeclarationLines;

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
    }

    override void visit(const ArrayInitializer arrayInitializer)
    {
        astInformation.arrayStartLocations ~= arrayInitializer.startLocation;
        arrayInitializer.accept(this);
    }

    override void visit(const ConditionalDeclaration dec)
    {
        if (dec.falseDeclaration !is null)
        {
            auto condition = dec.compileCondition;
            if (condition.versionCondition !is null)
            {
                astInformation.conditionalWithElseLocations ~= condition.versionCondition.versionIndex;
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
        astInformation.funLitStartLocations ~= funcLit.functionBody.blockStatement.startLocation;
        astInformation.funLitEndLocations ~= funcLit.functionBody.blockStatement.endLocation;
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

    override void visit(const FunctionBody functionBody)
    {
        if (functionBody.blockStatement !is null)
            astInformation.doubleNewlineLocations ~= functionBody.blockStatement.endLocation;
        if (functionBody.bodyStatement !is null && functionBody.bodyStatement.blockStatement !is null)
            astInformation.doubleNewlineLocations ~= functionBody.bodyStatement.blockStatement.endLocation;
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
                || unary.prefix.type == tok!"*" || unary.prefix.type == tok!"+"
                || unary.prefix.type == tok!"-")
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
    alias visit = ASTVisitor.visit;
}
