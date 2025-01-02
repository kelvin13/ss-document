extension HTML
{
    /// A type that wraps its ``display [requirement]`` value in an `a` element with `href` set
    /// to a fragment pointing to its ``Identifiable/id [requirement]`` value.
    public
    protocol OutputStreamableHeading<Display>:HTML.OutputStreamableAnchor
    {
        associatedtype Display:HTML.OutputStreamable = String

        var display:Display { get }
    }
}
/// The name of this protocol is ``HTML.OutputStreamableHeading``.
extension HTML.OutputStreamableHeading<String> where Self:CustomStringConvertible
{
    @inlinable public
    var display:String { self.description }
}
