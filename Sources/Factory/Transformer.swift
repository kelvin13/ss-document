import SwiftSyntax 

extension CustomAttributeSyntax 
{
    var simpleName:String? 
    {
        if  case .identifier(let name)? = 
            self.attributeName.as(SimpleTypeIdentifierSyntax.self)?.name.tokenKind
        {
            return name 
        }
        else 
        {
            return nil
        }
    }
}

extension AttributeListSyntax?
{
    // this is going to be slow no matter what, 
    // see https://github.com/apple/swift-syntax/issues/592
    mutating 
    func strip<T>(_ strip:(Wrapped.Element) throws -> T?) rethrows -> [T]?
    {
        var stripped:[T] = []
        var current:Int = 0
        while let list:Wrapped = self
        {
            let index:Wrapped.Index = list.index(list.startIndex, offsetBy: current)
            guard index < list.endIndex 
            else 
            {
                break
            }
            if let value:T = try strip(list[index])
            {
                stripped.append(value)
                self = list.count == 1 ? nil : list.removing(childAt: current)
            }
            else 
            {
                current += 1
            }
        }
        return stripped.isEmpty ? nil : stripped
    }
}

extension VariableDeclSyntax 
{
    func bases() -> PatternBindingListSyntax? 
    {
        var scratch:Self = self 
        let basis:[Void]? = scratch.removeAttributes
        {
            if  let attribute:CustomAttributeSyntax = $0.as(CustomAttributeSyntax.self), 
                case "basis"? = attribute.simpleName
            {
                return ()
            }
            else 
            {
                return nil
            }
        }
        if case _? = basis 
        {
            return self.bindings
        }
        else 
        {
            return nil
        }
    }
}

final 
class Transformer:SyntaxRewriter 
{
    var scope:[[String: [ExprSyntax]]] = []

    override 
    init() 
    {
        super.init() 
        self.scope = []
    }

    final private 
    func expand(_ declaration:DeclSyntax) -> [DeclSyntax]?
    {
        if  let expandable:any MatrixElement = 
            declaration.asProtocol(DeclSyntaxProtocol.self) as? MatrixElement
        {
            return expandable.expand(scope: self.scope)
        }
        else 
        {
            return nil
        }
    }

    final private 
    func with<T>(scope bindings:[PatternBindingListSyntax]?, _ body:() throws -> T) rethrows -> T 
    {
        guard let bindings:[PatternBindingListSyntax], !bindings.isEmpty
        else 
        {
            return try body()
        }

        var scope:[String: [ExprSyntax]] = [:]
        for binding:PatternBindingSyntax in bindings.joined() 
        {
            guard let pattern:IdentifierPatternSyntax = 
                binding.pattern.as(IdentifierPatternSyntax.self)
            else 
            {
                fatalError("expected let binding")
            }
            guard   let clause:InitializerClauseSyntax = binding.initializer, 
                    let array:ArrayExprSyntax = clause.value.as(ArrayExprSyntax.self)
            else 
            {
                fatalError("expected array literal")
            }
            
            scope[pattern.identifier.text] = array.elements.map { $0.expression.withoutTrivia() }
        }
            self.scope.append(scope)
        defer 
        {
            self.scope.removeLast()
        }
        return try body()
    }

    final override 
    func visit(_ list:CodeBlockItemListSyntax) -> Syntax
    {
        var list:CodeBlockItemListSyntax = list 
        let bindings:[PatternBindingListSyntax] = list.remove 
        {
            $0.item.as(VariableDeclSyntax.self).flatMap { $0.bases() }
        }
        return self.with(scope: bindings)
        {
            // expand nested blocks *before* expanding outer block 
            let list:Syntax = super.visit(list)
            guard let list:CodeBlockItemListSyntax = list.as(CodeBlockItemListSyntax.self) 
            else 
            {
                return list 
            }
            var elements:[CodeBlockItemSyntax] = []
                elements.reserveCapacity(list.count)
            for element:CodeBlockItemSyntax in list 
            { 
                guard let declaration:DeclSyntax = element.item.as(DeclSyntax.self), 
                        let expanded:[DeclSyntax] = self.expand(declaration)
                else 
                {
                    elements.append(element)
                    continue 
                }
                for element:DeclSyntax in expanded 
                {
                    elements.append(.init(item: Syntax.init(element), 
                        semicolon: nil, errorTokens: nil))
                }
            }
            return .init(CodeBlockItemListSyntax.init(elements))
        }
    }
    final override 
    func visit(_ list:MemberDeclListSyntax) -> Syntax
    {
        var list:MemberDeclListSyntax = list 
        let bindings:[PatternBindingListSyntax]? = list.remove 
        {
            $0.decl.as(VariableDeclSyntax.self).flatMap { $0.bases() }
        }
        return self.with(scope: bindings)
        {
            // expand nested blocks *before* expanding outer block 
            let list:Syntax = super.visit(list)
            guard let list:MemberDeclListSyntax = list.as(MemberDeclListSyntax.self) 
            else 
            {
                return list 
            }
            var elements:[MemberDeclListItemSyntax] = []
                elements.reserveCapacity(list.count)
            for element:MemberDeclListItemSyntax in list 
            { 
                guard let expanded:[DeclSyntax] = self.expand(element.decl)
                else 
                {
                    elements.append(element)
                    continue 
                }
                for element:DeclSyntax in expanded 
                {
                    elements.append(.init(decl: element, semicolon: nil))
                }
            }
            return .init(MemberDeclListSyntax.init(elements))
        }
    }
}