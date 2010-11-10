/*
 * WKTextView.j
 * WyzihatKit
 *
 * Created by Alexander Ljungberg, WireLoad LLC.
 *
 */

@implementation _WKWebView : CPWebView

- (DOMWindow)DOMWindow
{
    var contentWindow = nil;
    try
    {
        contentWindow = [super DOMWindow];
    }
    catch (e)
    {
    //  Do nothing.  When the Web View is not added to the DOM, it booms.
    //  Just ignore the boom because WKTextView checks multiple times.
    }
    return contentWindow;
}

@end

WKTextCursorHeightFactor    = 0.2;
WKTextViewInnerPadding      = 4;
WKTextViewDefaultFont       = "Verdana";

_CancelEvent = function(ev) {
    if (!ev)
        ev = window.event;
    if (ev && ev.stopPropagation)
        ev.stopPropagation();
    else if (ev && ev.cancelBubble)
        ev.cancelBubble = true;
}

_EditorEvents = [
    'onmousedown',
    'onmouseup',
    'onkeypress',
    'onkeydown',
    'onkeyup'
]

/*!
    A WYSIHAT based rich text editor widget.

    Beware of the load times. Wait for the load event.
*/
@implementation WKTextView : _WKWebView
{
    id              delegate @accessors;
    CPTimer         loadTimer;
    Object          editor;
    Object          _scrollDiv;
    BOOL            shouldFocusAfterAction;
    BOOL            suppressAutoFocus;
    BOOL            editable;
    BOOL            enabled;
    BOOL            autohidesScrollers @accessors;

    CPString        _html;

    CPString        lastFont;
    CPString        lastColorString;
    CPColor         lastColor;
    CPDictionary    eventHandlerSwizzler;

    CPScroller      _verticalScroller;
    float           _verticalLineScroll;
    float           _verticalPageScroll;

}

- (id)initWithFrame:(CGRect)aFrame
{
    if (self = [super initWithFrame:aFrame])
    {
        lastColor = [CPColor blackColor];

        _verticalPageScroll = 10;
        _verticalLineScroll = 10;

        autohidesScrollers = YES;

        [self setDrawsBackground:NO];
        [self setBackgroundColor:[CPColor whiteColor]];

        eventHandlerSwizzler = [[CPDictionary alloc] init];
        shouldFocusAfterAction = YES;
        [self setEditable: YES];
        [self setEnabled: YES];
        [self setScrollMode:CPWebViewScrollNative];
        [self setMainFrameURL:[[CPBundle bundleForClass:[WKTextView class]] pathForResource:"WKTextView/editor.html"]];

        _verticalScroller = [[CPScroller alloc] initWithFrame:CGRectMake(0.0, 0.0, [CPScroller scrollerWidth], MAX(CGRectGetHeight([self bounds]), [CPScroller scrollerWidth] + 1))];
        [_verticalScroller setAutoresizingMask:CPViewMinXMargin];
        [_verticalScroller setTarget:self];
        [_verticalScroller setAction:@selector(_verticalScrollerDidScroll:)];

        [self addSubview:_verticalScroller];
        [self _updateScrollbar];

        // Check if the document was loaded immediately. This could happen if we're loaded from
        // a file URL.
        [self checkLoad];
    }
    return self;
}

- (void)_startedLoading
{
    // If the frame reloads for whatever reason, the editor is gone.
    editor = nil;
    [super _startedLoading];
}

- (void)_finishedLoading
{
    [super _finishedLoading];
    [self checkLoad];
}

- (void)checkLoad
{
    // Is the editor ready?
    var maybeEditor = [self objectByEvaluatingJavaScriptFromString:"typeof(__wysihat_editor) != 'undefined' ? __wysihat_editor : null"];
    if (maybeEditor && maybeEditor.parentNode && maybeEditor.parentNode.parentNode)
    {
        [self setEditor:maybeEditor];

        if (loadTimer)
        {
            [loadTimer invalidate];
            loadTimer = nil;
         }

        if (_html != nil)
            [self editor].innerHTML = _html;

        if ([delegate respondsToSelector:@selector(textViewDidLoad:)])
        {
            [delegate textViewDidLoad:self];
        }
    }
    else
    {
        if (!loadTimer)
            loadTimer = [CPTimer scheduledTimerWithTimeInterval:0.1 target:self selector:"checkLoad" userInfo:nil repeats:YES];
    }
}

- (BOOL)acceptsFirstResponder
{
    return (editor !== nil && [self isEditable] && [self isEnabled]);
}

- (BOOL)becomeFirstResponder
{
    [self _didBeginEditing];
    editor.focus();
    return YES;
}

- (BOOL)resignFirstResponder
{
    window.focus();
    [self _didEndEditing];
    return YES;
}

/*!
    Sets whether or not the receiver text view can be edited.
*/
- (void)setEditable:(BOOL)shouldBeEditable
{
    editable = shouldBeEditable;
}

/*!
    Returns \c YES if the text view is currently editable by the user.
*/
- (BOOL)isEditable
{
    return editable;
}

/*!
    Sets whether or not the receiver text view is enabled.
*/
- (void)setEnabled:(BOOL)shouldBeEnabled
{
    enabled = shouldBeEnabled;
    if (editor)
    {
        editor.contentEditable = enabled ? 'true' : 'false';
        // When contentEditable is off we must disable wysihat event handlers
        // or they'll cause errors e.g. if a user clicks a disabled WKTextView.
        var t = editor;
        for (var i = 0; i < _EditorEvents.length; i++)
        {
            var ev = _EditorEvents[i];
            if (!enabled && t[ev] !== _CancelEvent)
            {
                [eventHandlerSwizzler setObject:t[ev] forKey:ev];
                t[ev] = _CancelEvent;
            }
            else if (enabled && t[ev] === _CancelEvent)
            {
                t[ev] = [eventHandlerSwizzler objectForKey:ev];
            }
        }
    }
}

- (void)setAutohidesScrollers:(BOOL)aFlag
{
    if (autohidesScrollers === aFlag)
        return;

    autohidesScrollers = aFlag;

    [self _updateScrollbar];
}

/*!
    Returns \c YES if the text view is currently enabled.
*/
- (BOOL)isEnabled
{
    return enabled;
}

/*!
    Sets whether the editor should automatically take focus after an action
    method is invoked such as boldSelection or setFont. This is useful when
    binding to a toolbar.
*/
- (void)setShouldFocusAfterAction:(BOOL)aFlag
{
    shouldFocusAfterAction = aFlag;
}

- (BOOL)shouldFocusAfterAction
{
    return shouldFocusAfterAction;
}

- (void)setEditor:anEditor
{
    if (editor === anEditor)
        return;

    if (![self DOMWindow])
        return;

    editor = anEditor;
    _scrollDiv = editor.parentNode.parentNode;
    _iframe.allowTransparency = true;

    [self DOMWindow].document.body.style.backgroundColor = 'transparent';

    // FIXME execCommand doesn't work well without the view having been focused
    // on at least once.
    // editor.focus();

    suppressAutoFocus = YES;
    [self setFontNameForSelection:WKTextViewDefaultFont];
    suppressAutoFocus = NO;

    if (editor['WKTextView_Installed'] === undefined)
    {
        var doc = [self DOMWindow].document;

        var onmousedown = function(ev) {
            if (!ev)
                ev = window.event;
            var win = [self window];
            if ([win firstResponder] === self)
                return YES;
            // We have to emulate select pieces of CPWindow's event handling
            // here since the iframe bypasses the regular event handling.
            var becameFirst = false;
            if ([self acceptsFirstResponder])
            {
                becameFirst = [win makeFirstResponder:self];
                if (becameFirst)
                {
                    if (![win isKeyWindow])
                        [win makeKeyAndOrderFront:self];
                    [[CPRunLoop currentRunLoop] limitDateForMode:CPDefaultRunLoopMode];
                }
            }
            // If selection was successful, allow the event to continue propagate so that the
            // cursor is placed in the right spot.
            return becameFirst;
        }

        defaultKeydown = doc.onkeydown;
        var onkeydown = function(ev) {
            if (!ev)
                ev = window.event;

            var key = ev.keyCode;
            if (!key)
                key = ev.which;

            // Shift+Tab
            if (ev.shiftKey && key == 9)
            {
                setTimeout(function()
                {
                    [[self window] selectPreviousKeyView:self];
                    [[CPRunLoop currentRunLoop] limitDateForMode:CPDefaultRunLoopMode];
                }, 0.0);
                return false;
            }
            else
            {
                if (defaultKeydown)
                    return defaultKeydown(ev);
                return true;
            }
        };

        var onscroll = function(ev) {
            if (!ev)
                ev = window.event;

            [self _updateScrollbar];
            [[CPRunLoop currentRunLoop] limitDateForMode:CPDefaultRunLoopMode];
            return true;
        }

        if (doc.addEventListener)
        {
            doc.addEventListener('mousedown', onmousedown, true);
            doc.addEventListener('keydown', onkeydown, true);
            doc.body.addEventListener('scroll', onscroll, true);
        }
        else if (doc.attachEvent)
        {
            doc.attachEvent('onmousedown', onmousedown);
            doc.attachEvent('onkeydown', onkeydown);
            doc.body.attachEvent('scroll', onscroll);
        }

        editor.observe("field:change", function() {
            [self _didChange];
            // The normal run loop doesn't react to iframe events, so force immediate processing.
            [[CPRunLoop currentRunLoop] limitDateForMode:CPDefaultRunLoopMode];
        });
        editor.observe("selection:change", function() {
            [self _cursorDidMove];
            // The normal run loop doesn't react to iframe events, so force immediate processing.
            [[CPRunLoop currentRunLoop] limitDateForMode:CPDefaultRunLoopMode];
        });

        editor['WKTextView_Installed'] = true;
    }

    [self _resizeWebFrame];
    [self setEnabled:enabled];
}

- (JSObject)editor
{
    return editor;
}

- (void)_updateScrollbar
{
    var scrollTop = 0,
        height = 1,
        frameHeight = CGRectGetHeight([self bounds]),
        scrollerWidth = CGRectGetWidth([_verticalScroller bounds]);

    if (_scrollDiv)
    {
        scrollTop = _scrollDiv.scrollTop;
        height = _scrollDiv.scrollHeight;
    }
    height = MAX(1, height);

    var difference = height - frameHeight,
        proportion = frameHeight / height;

    // Avoid showing the scrollbar when it would nearly fill the bar anyhow.
    // This avoids the bar flickering like crazy when animating the text field
    // growing or shrinking, as could otherwise happen due to the inner height
    // not having updated yet to fit to the outter height when the scroll bar
    // update happens.
    if (proportion > 0.99)
        proportion = 1;

    // Additionally, hide the scroller if there is no need to show one.
    [_verticalScroller setHidden:autohidesScrollers && proportion == 1];

    [_verticalScroller setFloatValue:scrollTop / difference];
    [_verticalScroller setKnobProportion:proportion];
    [_verticalScroller setFrame:CGRectMake(CGRectGetMaxX([self bounds])-scrollerWidth, 0, scrollerWidth, frameHeight)];
}

- (void)_verticalScrollerDidScroll:(CPScroller)aScroller
{
    if (!_scrollDiv)
        return; // Shouldn't happen. No editor means no scrollbar.

    // Based on CPScrollView _verticalScrollerDidScroll
    var scrollTop = _scrollDiv.scrollTop,
        height = _scrollDiv.scrollHeight,
        frameHeight = CGRectGetHeight([self bounds]),
        value = [aScroller floatValue];

    switch ([_verticalScroller hitPart])
    {
        case CPScrollerDecrementLine:   scrollTop -= _verticalLineScroll;
                                        break;

        case CPScrollerIncrementLine:   scrollTop += _verticalLineScroll;
                                        break;

        case CPScrollerDecrementPage:   scrollTop -= frameHeight - _verticalPageScroll;
                                        break;

        case CPScrollerIncrementPage:   scrollTop += frameHeight - _verticalPageScroll;
                                        break;

        case CPScrollerKnobSlot:
        case CPScrollerKnob:
                                        // We want integral bounds!
        default:                        scrollTop = ROUND(value * (height - frameHeight));
    }

    _scrollDiv.scrollTop = scrollTop;
}

- (void)_didChange
{
	[self willChangeValueForKey:@"htmlValue"];

    // When the text changes, the height of the content may change.
    [self _updateScrollbar];

    if ([delegate respondsToSelector:@selector(textViewDidChange:)])
    {
        [delegate textViewDidChange:self];
    }

	[self didChangeValueForKey:@"htmlValue"];

}

- (void)_didBeginEditing
{
    if ([delegate respondsToSelector:@selector(textViewDidBeginEditing:)])
        [delegate textViewDidBeginEditing:self];
}

- (void)_didEndEditing
{
    if ([delegate respondsToSelector:@selector(textViewDidEndEditing:)])
        [delegate textViewDidEndEditing:self];
}

- (void)_cursorDidMove
{
    if (![self DOMWindow])
        return;

    if ([delegate respondsToSelector:@selector(textViewCursorDidMove:)])
    {
        [delegate textViewCursorDidMove:self];
    }
}

- (void)_resizeWebFrame
{
    if (editor)
        editor.style.minHeight = (CGRectGetHeight([self bounds])-(2+WKTextViewInnerPadding*2)) + "px";
    [self _updateScrollbar];
}

- (void)_loadMainFrameURL
{
    [self _startedLoading];

    _ignoreLoadStart = YES;
    _ignoreLoadEnd = NO;

    _url = _mainFrameURL;
    _html = null;

    [self _load];
}

- (void)_addKeypressHandler:(Function)aFunction
{
    if ([self editor])
    {
        var doc = [self DOMWindow].document;
        if (doc.addEventListener)
        {
            doc.addEventListener('keypress', aFunction, true);
        }
        else if (doc.attachEvent)
        {
            doc.attachEvent('onkeypress',
                            function() { aFunction([self editor].event) });
            //This needs to be tested in IE. I have no idea if [self editor] will have an event
        }
    }
}

- (CPString)htmlValue
{

    if ([self editor] != nil)
    return [self editor].innerHTML;
    	
    return _html;
}

- (void)setHtmlValue:(CPString)html
{
    [self willChangeValueForKey:@"htmlValue"];

    _html = html;
	
    if ([self editor] != nil)
        [self editor].innerHTML = html;

    [self _didChange];

    [self didChangeValueForKey:@"htmlValue"];
}

- (CPString)textValue
{
    return [self editor].content();
}

- (void)setTextValue:(CPString)content
{
    [self editor].setContent(content);
    [self _didChange];
}

- (void)_didPerformAction
{
    if (shouldFocusAfterAction && !suppressAutoFocus)
    {
        [self DOMWindow].focus();
    }
}

- (@action)clearText:(id)sender
{
    [self setHtmlValue:""];
    [self _didChange];
    [self _didPerformAction];
}

- (void)insertHtml:(CPString)html
{
    [self editor].insertHTML(html);
    [self _didChange];
    [self _didPerformAction];
}

- (@action)boldSelection:(id)sender
{
    [self editor].boldSelection();
    [self _didPerformAction];
}

- (@action)underlineSelection:(id)sender
{
    [self editor].underlineSelection();
    [self _didPerformAction];
}

- (@action)italicSelection:(id)sender
{
    [self editor].italicSelection();
    [self _didPerformAction];
}

- (@action)strikethroughSelection:(id)sender
{
    [self editor].strikethroughSelection();
    [self _didPerformAction];
}

- (@action)alignSelectionLeft:(id)sender
{
    [self editor].alignSelection('left');
    [self _didPerformAction];
}

- (@action)alignSelectionRight:(id)sender
{
    [self editor].alignSelection('right');
    [self _didPerformAction];
}

- (@action)alignSelectionCenter:(id)sender
{
    [self editor].alignSelection('center');
    [self _didPerformAction];
}

- (@action)alignSelectionFull:(id)sender
{
    [self editor].alignSelection('full');
    [self _didPerformAction];
}

- (@action)linkSelection:(id)sender
{
    // TODO Show a sheet asking for a URL to link to.
}

- (void)linkSelectionToURL:(CPString)aUrl
{
    [self editor].linkSelection(aUrl);
    [self _didPerformAction];
}

- (void)unlinkSelection:(id)sender
{
    [self editor].unlinkSelection();
    [self _didPerformAction];
}

- (@action)insertOrderedList:(id)sender
{
    [self editor].insertOrderedList();
    [self _didPerformAction];
}

- (@action)insertUnorderedList:(id)sender
{
    [self editor].insertUnorderedList();
    [self _didPerformAction];
}

- (@action)insertImage:(id)sender
{
    // TODO Show a sheet asking for an image URL.
}

- (void)insertImageWithURL:(CPString)aUrl
{
    [self editor].insertImage(aUrl);
    [self _didPerformAction];
}

- (void)setFontNameForSelection:(CPString)font
{
    lastFont = font;
    [self editor].fontSelection(font);
    [self _didPerformAction];
}

- (int)fontSizeRaw
{
    try {
        return [self DOMWindow].document.queryCommandValue('fontsize');
    } catch(e) {
        return "16px";
    }
}

- (int)fontSize
{
    // Strangely we get font sizes back in pixels.
    var size = parseInt([self fontSizeRaw]),
        sizeMap = { 10:1, 13:2, 16:3, 18:4, 24:5, 32:6, 48:7};
    if (size <= 7)
        return size;
    else if (size in sizeMap)
        return sizeMap[size];
    else
        return 3;
}

/*!
    Set the font size for the selected text. Size is specified
    as a number between 1-6 which corresponds to small through xx-large.
*/
- (void)setFontSizeForSelection:(int)size
{
    [self editor].fontSizeSelection(size);
    [self _didPerformAction];
}

- (CPString)font
{
    try
    {
        var fontName = [self DOMWindow].document.queryCommandValue('fontname');
    } catch(e) {
        return lastFont;
    }

    // The font name may come through with quotes e.g. 'Apple Chancery'
    var format = /'(.*?)'/,
        r = fontName ? fontName.match(new RegExp(format)) : nil;

    if (r && r.length == 2)
        lastFont = r[1];
    else if (fontName)
        lastFont = fontName;

    return lastFont;
}

- (CPColor)color
{
    var colorString;
    try {
        colorString = [self DOMWindow].document.queryCommandValue('forecolor');
    } catch(e) {
        console.error(e);
    }
    // Avoid creating a new Color instance every time the cursor moves by reusing the last
    // instance.
    if (!colorString || colorString == lastColorString)
        return lastColor;
    lastColor = [[CPColor alloc] _initWithCSSString:colorString];
    lastColorString = colorString;
    return lastColor;
}

- (void)setColorForSelection:(CPColor)aColor
{
    [self editor].colorSelection([aColor hexString]);
    [self _didPerformAction];
}
