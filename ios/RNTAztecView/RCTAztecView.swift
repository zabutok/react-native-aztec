import Aztec
import CoreServices
import Foundation
import UIKit
import AVFoundation

class RCTAztecView: Aztec.TextView, UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate  {
    @objc var onBackspace: RCTBubblingEventBlock? = nil
    @objc var onChange: RCTBubblingEventBlock? = nil
    @objc var onKeyDown: RCTBubblingEventBlock? = nil
    @objc var onEnter: RCTBubblingEventBlock? = nil
    @objc var onFocus: RCTBubblingEventBlock? = nil
    @objc var onBlur: RCTBubblingEventBlock? = nil
    @objc var onPaste: RCTBubblingEventBlock? = nil
    @objc var onContentSizeChange: RCTBubblingEventBlock? = nil
    @objc var onSelectionChange: RCTBubblingEventBlock? = nil
    @objc var onActiveFormatsChange: RCTBubblingEventBlock? = nil
    @objc var minWidth: CGFloat = 0
    @objc var maxWidth: CGFloat = 0
    @objc var triggerKeyCodes: NSArray?
    @objc var headers: NSDictionary?
    @objc var parameters: NSDictionary?
    @objc var imageUrl: NSString?

    @objc var activeFormats: NSSet? = nil {
        didSet {
            let currentTypingAttributes = formattingIdentifiersForTypingAttributes()
            for (key, value) in formatStringMap where currentTypingAttributes.contains(key) != activeFormats?.contains(value) {
                toggleFormat(format: value)
            }
        }
    }

    fileprivate(set) lazy var mediaInserter: MediaInserter = {
        return MediaInserter(textView: self, attachmentTextAttributes: Constants.mediaMessageAttributes)
    }()

    fileprivate(set) lazy var textViewAttachmentDelegate: TextViewAttachmentDelegate = {
        let presentedViewController = RCTPresentedViewController();
        let textAttachmentDelegate = TextViewAttachmentDelegateProvider(baseController: presentedViewController!, attachmentTextAttributes: Constants.mediaMessageAttributes)
        self.textAttachmentDelegate = textAttachmentDelegate
        return textAttachmentDelegate

    }()

    static var tintedMissingImage: UIImage = {
        if #available(iOS 13.0, *) {
            return UIImage.init(systemName: "photo")!.withTintColor(.label)
        } else {
            // Fallback on earlier versions
            return UIImage(named: "photo")!
        }
    }()
    struct Constants {
        static let defaultContentFont   = UIFont.systemFont(ofSize: 14)
        static let defaultHtmlFont      = UIFont.systemFont(ofSize: 24)
        static let defaultMissingImage  = tintedMissingImage
        static let formatBarIconSize    = CGSize(width: 20.0, height: 20.0)
        static let headers              = [Header.HeaderType.none, .h1, .h2, .h3, .h4, .h5, .h6]
        static let lists                = [TextList.Style.unordered, .ordered]
        static let moreAttachmentText   = "more"
        static let titleInsets          = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 0)
        static var mediaMessageAttributes: [NSAttributedString.Key: Any] {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                                                            .paragraphStyle: paragraphStyle,
                                                            .foregroundColor: UIColor.white]
            return attributes
        }
    }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        // Local variable inserted by Swift 4.2 migrator.
        let info = convertFromUIImagePickerControllerInfoKeyDictionary(info)
        let presentedViewController = RCTPresentedViewController();
        presentedViewController!.dismiss(animated: true, completion: nil)
//        dismiss(animated: true, completion: nil)
//        richTextView.becomeFirstResponder()
        guard let mediaType =  info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.mediaType)] as? String else {
            return
        }
        let typeImage = kUTTypeImage as String
        let typeMovie = kUTTypeMovie as String

        switch mediaType {
        case typeImage:
            guard let image = info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.originalImage)] as? UIImage else {
                return
            }

            // Insert Image + Reclaim Focus
            mediaInserter.insertImage(image, imageUrl: imageUrl,headers: headers, parameters: parameters)

        case typeMovie:
            guard let videoURL = info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.mediaURL)] as? URL else {
                return
            }
            mediaInserter.insertVideo(videoURL)
        default:
            print("Media type not supported: \(mediaType)")
        }
    }

    fileprivate func convertFromUIImagePickerControllerInfoKeyDictionary(_ input: [UIImagePickerController.InfoKey: Any]) -> [String: Any] {
        return Dictionary(uniqueKeysWithValues: input.map {key, value in (key.rawValue, value)})
    }

    // Helper function inserted by Swift 4.2 migrator.
    fileprivate func convertFromUIImagePickerControllerInfoKey(_ input: UIImagePickerController.InfoKey) -> String {
        return input.rawValue
    }

    @objc var disableEditingMenu: Bool = false {
        didSet {
            allowsEditingTextAttributes = !disableEditingMenu
        }
    }

    @objc var disableAutocorrection: Bool = false {
        didSet {
            autocorrectionType = disableAutocorrection ? .no : .default
        }
    }

    override var textAlignment: NSTextAlignment {
        set {
            super.textAlignment = newValue
            defaultParagraphStyle.alignment = newValue
            placeholderLabel.textAlignment = newValue
        }

        get {
            return super.textAlignment
        }
    }

    private var previousContentSize: CGSize = .zero

    var leftTextInset: CGFloat {
        return contentInset.left + textContainerInset.left + textContainer.lineFragmentPadding
    }

    var leftTextInsetInRTLLayout: CGFloat {
        return bounds.width - leftTextInset
    }

    var hasRTLLayout: Bool {
        return reactLayoutDirection == .rightToLeft
    }

    private(set) lazy var placeholderLabel: UILabel = {
        let label = UILabel(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .natural
        label.font = font

        return label
    }()

    // RCTScrollViews are flipped horizontally on RTL. This messes up competelly horizontal layout contraints
    // on views inserted after the transformation.
    var placeholderPreferedHorizontalAnchor: NSLayoutXAxisAnchor {
        return hasRTLLayout ? placeholderLabel.rightAnchor : placeholderLabel.leftAnchor
    }

    // This constraint is created from the prefered horizontal anchor (analog to "leading")
    // but appending it always to left of its super view (Aztec).
    // This partially fixes the position issue originated from fliping the scroll view.
    // fixLabelPositionForRTLLayout() fixes the rest.
    private lazy var placeholderHorizontalConstraint: NSLayoutConstraint = {
        return placeholderPreferedHorizontalAnchor.constraint(
            equalTo: leftAnchor,
            constant: leftTextInset
        )
    }()

    private lazy var placeholderWidthConstraint: NSLayoutConstraint = {
        // width needs to be shrunk on both the left and the right by the textInset in order for
        // the placeholder to be appropriately positioned with right alignment.
        let placeholderWidthInset = 2 * leftTextInset
        return placeholderLabel.widthAnchor.constraint(equalTo: widthAnchor, constant: -placeholderWidthInset)
    }()

    /// If a dictation start with an empty UITextView,
    /// the dictation engine refreshes the TextView with an empty string when the dictation finishes.
    /// This helps to avoid propagating that unwanted empty string to RN. (Solving #606)
    /// on `textViewDidChange` and `textViewDidChangeSelection`
    private var isInsertingDictationResult = false

    // MARK: - Font

    /// Flag to enable using the defaultFont in Aztec for specific blocks
    /// Like the Preformatted and Heading blocks.
    private var blockUseDefaultFont: Bool = false

    /// Font family for all contents  Once this is set, it will always override the font family for all of its
    /// contents, regardless of what HTML is provided to Aztec.
    private var fontFamily: String? = nil

    /// Font size for all contents.  Once this is set, it will always override the font size for all of its
    /// contents, regardless of what HTML is provided to Aztec.
    private var fontSize: CGFloat? = nil

    /// Font weight for all contents.  Once this is set, it will always override the font weight for all of its
    /// contents, regardless of what HTML is provided to Aztec.
    private var fontWeight: String? = nil

    /// Line height for all contents.  Once this is set, it will always override the font size for all of its
    /// contents, regardless of what HTML is provided to Aztec.
    private var lineHeight: CGFloat? = nil

    // MARK: - Formats

    private let formatStringMap: [FormattingIdentifier: String] = [
        .bold: "bold",
        .italic: "italic",
        .strikethrough: "strikethrough",
        .link: "link",
        .mark: "mark"
    ]

    override init(defaultFont: UIFont, defaultParagraphStyle: ParagraphStyle, defaultMissingImage: UIImage) {
        super.init(defaultFont: defaultFont, defaultParagraphStyle: defaultParagraphStyle, defaultMissingImage: defaultMissingImage)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Configuration.headersWithBoldTrait = true
        delegate = self
        textContainerInset = .zero
        contentInset = .zero
        textContainer.lineFragmentPadding = 0
        frame.size = .zero
        addPlaceholder()
        textDragInteraction?.isEnabled = false
        storage.htmlConverter.characterToReplaceLastEmptyLine = Character(.zeroWidthSpace)
        storage.htmlConverter.shouldCollapseSpaces = false
        shouldNotifyOfNonUserChanges = false
        // Typing attributes are controlled by RichText component so we have to prevent Aztec to recalculate them when deleting backward.
        shouldRecalculateTypingAttributesOnDeleteBackward = false
        disableLinkTapRecognizer()
        preBackgroundColor = .clear
    }

    func addPlaceholder() {
        addSubview(placeholderLabel)
        let topConstant = contentInset.top + textContainerInset.top
        NSLayoutConstraint.activate([
            placeholderHorizontalConstraint,
            placeholderWidthConstraint,
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: topConstant)
        ])
    }

    /**
     This handles a bug introduced by iOS 13.0 (tested up to 13.2) where link interactions don't respect what the documentation says.

     The documenatation for textView(_:shouldInteractWith:in:interaction:) says:

     > Links in text views are interactive only if the text view is selectable but noneditable.

     Our Aztec Text views are selectable and editable, and yet iOS was opening links on Safari when tapped.
     */
    func disableLinkTapRecognizer() {
        guard let recognizer = gestureRecognizers?.first(where: { $0.name == "UITextInteractionNameLinkTap" }) else {
            return
        }
        recognizer.isEnabled = false
    }

    // MARK: - View height and width: Match to the content

    override func layoutSubviews() {
        super.layoutSubviews()
        adjustWidth()
        fixLabelPositionForRTLLayout()
        updateContentSizeInRN()
    }

    private func adjustWidth() {
        if (maxWidth > 0 && minWidth > 0) {
            let maxSize = CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
            let newWidth = sizeThatFits(maxSize).width
            if (newWidth != frame.size.width) {
                frame.size.width = max(newWidth, minWidth)
            }
        }
    }

    private func fixLabelPositionForRTLLayout() {
        if hasRTLLayout {
            // RCTScrollViews are flipped horizontally on RTL layout.
            // This fixes the position of the label after "fixing" (partially) the constraints.
            placeholderHorizontalConstraint.constant = leftTextInsetInRTLLayout
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        // Set the Placeholder height as the minimum TextView height.
        let minimumHeight = placeholderLabel.frame.height
        let fittingSize = super.sizeThatFits(size)
        let height = max(fittingSize.height, minimumHeight)
        return CGSize(width: fittingSize.width, height: height)
    }

    func updateContentSizeInRN() {
        let newSize = sizeThatFits(frame.size)

        guard previousContentSize != newSize,
            let onContentSizeChange = onContentSizeChange else {
                return
        }

        previousContentSize = newSize

        let body = packForRN(newSize, withName: "contentSize")
        onContentSizeChange(body)
    }

    // MARK: - Paste handling
    private func read(from pasteboard: UIPasteboard, uti: CFString, documentType: DocumentType) -> String? {
        guard let data = pasteboard.data(forPasteboardType: uti as String),
            let attributedString = try? NSAttributedString(data: data, options: [.documentType: documentType], documentAttributes: nil),
            let storage = self.textStorage as? TextStorage else {
                return nil
        }
        return  storage.getHTML(from: attributedString)
    }

    private func readHTML(from pasteboard: UIPasteboard) -> String? {

        if let data = pasteboard.data(forPasteboardType: kUTTypeHTML as String), let html = String(data: data, encoding: .utf8) {
            // Make sure we are not getting a full HTML DOC. We only want inner content
            if !html.hasPrefix("<!DOCTYPE html") {
                return html
            }
        }

        if let flatRTFDString = read(from: pasteboard, uti: kUTTypeFlatRTFD, documentType: DocumentType.rtfd) {
            return  flatRTFDString
        }

        if let rtfString = read(from: pasteboard, uti: kUTTypeRTF, documentType: DocumentType.rtf) {
            return  rtfString
        }

        if let rtfdString = read(from: pasteboard, uti: kUTTypeRTFD, documentType: DocumentType.rtfd) {
            return  rtfdString
        }

        return nil
    }

    private func readText(from pasteboard: UIPasteboard) -> String? {
        var text = pasteboard.string
        // Text that comes from Aztec will have paragraphSeparator instead of line feed AKA as \n. The paste methods in GB are expecting \n so this line will fix that.
        text = text?.replacingOccurrences(of: String(.paragraphSeparator), with: String(.lineFeed))
        return text
    }

    func saveToDisk(image: UIImage) -> URL? {
        let fileName = "\(ProcessInfo.processInfo.globallyUniqueString)_file.jpg"

        guard let data = image.jpegData(compressionQuality: 0.9) else {
            return nil
        }

        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)

        guard (try? data.write(to: fileURL, options: [.atomic])) != nil else {
            return nil
        }

        return fileURL
    }

    private func readImages(from pasteboard: UIPasteboard) -> [String] {
        guard let images = pasteboard.images else {
            return []
        }
        let imagesURLs = images.compactMap({ saveToDisk(image: $0)?.absoluteString })
        return imagesURLs
    }

    private func sendPasteCallback(text: String, html: String, imagesURLs: [String]) {
        let start = selectedRange.location
        let end = selectedRange.location + selectedRange.length
        onPaste?([
            "currentContent": cleanHTML(),
            "selectionStart": start,
            "selectionEnd": end,
            "pastedText": text,
            "pastedHtml": html,
            "files": imagesURLs] )
    }

    // MARK: - Edits

    open override func insertText(_ text: String) {
        guard !interceptEnter(text) else {
            return
        }

        interceptTriggersKeyCodes(text)

        super.insertText(text)
        updatePlaceholderVisibility()
    }

    open override func deleteBackward() {
        guard !interceptBackspace() else {
            return
        }

        super.deleteBackward()
        updatePlaceholderVisibility()
    }

    // MARK: - Dictation

    override func dictationRecordingDidEnd() {
        isInsertingDictationResult = true
    }

    public override func insertDictationResult(_ dictationResult: [UIDictationPhrase]) {
        let objectPlaceholder = "\u{FFFC}"
        let dictationText = dictationResult.reduce("") { $0 + $1.text }
        isInsertingDictationResult = false
        self.text = self.text?.replacingOccurrences(of: objectPlaceholder, with: dictationText)
    }

    // MARK: - Custom Edit Intercepts

    private func interceptEnter(_ text: String) -> Bool {
        if text == "\t" {
            return true
        }

        guard text == "\n",
            let onKeyDown = onKeyDown else {
                return false
        }

        var eventData = packCaretDataForRN()
        eventData = add(keyTrigger: "\r", to: eventData)
        onKeyDown(eventData)
        return true
    }

    private func interceptBackspace() -> Bool {
        guard (isNewLineBeforeSelectionAndNotEndOfContent() && selectedRange.length == 0)
            || (selectedRange.location == 0 && selectedRange.length == 0)
            || text.count == 1 // send backspace event when cleaning all characters
            || selectedRange == NSRange(location: 0, length: textStorage.length), // send backspace event when deleting all the text
            let onKeyDown = onKeyDown else {
                return false
        }
        var range = selectedRange
        if text.count == 1 {
            range = NSRange(location: 0, length: textStorage.length)
        }
        var caretData = packCaretDataForRN(overrideRange: range)
        onSelectionChange?(caretData)
        let backSpaceKeyCode:UInt8 = 8
        caretData = add(keyCode: backSpaceKeyCode, to: caretData)
        onKeyDown(caretData)
        return true
    }


    private func interceptTriggersKeyCodes(_ text: String) {
        guard let keyCodes = triggerKeyCodes,
            keyCodes.count > 0,
            let onKeyDown = onKeyDown,
            text.count == 1
        else {
            return
        }
        for value in keyCodes {
            guard let keyString = value as? String,
                let keyCode = keyString.first?.asciiValue,
                text.contains(keyString)
            else {
                continue
            }

            var eventData = [AnyHashable:Any]()
            eventData = add(keyCode: keyCode, to: eventData)
            onKeyDown(eventData)
            return
        }
    }

    private func isNewLineBeforeSelectionAndNotEndOfContent() -> Bool {
        guard let currentLocation = text.indexFromLocation(selectedRange.location) else {
            return false
        }

        return text.isStartOfParagraph(at: currentLocation) && !(text.endIndex == currentLocation)
    }
    override var keyCommands: [UIKeyCommand]? {
        // Remove defautls Tab and Shift+Tab commands, leaving just Shift+Enter command.
        return [carriageReturnKeyCommand]
    }

    // MARK: - Native-to-RN Value Packing Logic

    private func cleanHTML() -> String {
        let html = getHTML(prettify: false).replacingOccurrences(of: String(.paragraphSeparator), with: String(.lineFeed)).replacingOccurrences(of: String(.zeroWidthSpace), with: "")
        return html
    }

    func packForRN(_ text: String, withName name: String) -> [AnyHashable: Any] {
        return [name: text,
                "eventCount": 1]
    }

    func packForRN(_ size: CGSize, withName name: String) -> [AnyHashable: Any] {

        let size = ["width": size.width,
                    "height": size.height]

        return [name: size]
    }

    func packCaretDataForRN(overrideRange: NSRange? = nil) -> [AnyHashable: Any] {
        var range = selectedRange
        if let overrideRange = overrideRange {
            range = overrideRange
        }
        var start = range.location
        var end = range.location + range.length
        if selectionAffinity == .backward {
            (start, end) = (end, start)
        }

        var result: [AnyHashable : Any] = packForRN(cleanHTML(), withName: "text")

        result["selectionStart"] = start
        result["selectionEnd"] = end

        if let range = selectedTextRange {
            let caretEndRect = caretRect(for: range.end)
            // Sergio Estevao: Sometimes the carectRect can be invalid so we need to check before sending this to JS.
            if !(caretEndRect.isInfinite || caretEndRect.isNull) {
                result["selectionEndCaretX"] = caretEndRect.origin.x
                result["selectionEndCaretY"] = caretEndRect.origin.y
            }
        }

        return result
    }

    func add(keyTrigger: String, to pack:[AnyHashable: Any]) -> [AnyHashable: Any] {
        guard let keyCode = keyTrigger.first?.asciiValue else {
            return pack
        }
        return add(keyCode: keyCode, to: pack)
    }

    func add(keyCode: UInt8, to pack:[AnyHashable: Any]) -> [AnyHashable: Any] {
        var result = pack
        result["keyCode"] = keyCode
        return result
    }

    // MARK: - RN Properties

    @objc func setBlockUseDefaultFont(_ useDefaultFont: Bool) {
        guard blockUseDefaultFont != useDefaultFont else {
            return
        }

        if useDefaultFont {
            // Enable using the defaultFont in Aztec
            // For the PreFormatter and HeadingFormatter
            Configuration.useDefaultFont = true
        }

        blockUseDefaultFont = useDefaultFont
        refreshFont()
    }
    @objc
    func setHeadersData(_ data: NSDictionary) {
        headers = data;
    }
//    @objc
//    func setParameters(_ data: NSDictionary) {
//        parameters = data;
//    }
    @objc
    func setContents(_ contents: NSDictionary) {

        if let hexString = contents["linkTextColor"] as? String, let linkColor = UIColor(hexString: hexString), linkTextColor != linkColor {
            linkTextColor = linkColor
        }

        guard contents["eventCount"] == nil else {
            return
        }

        let html = contents["text"] as? String ?? ""

        let tag = contents["tag"] as? String ?? ""
        checkDefaultFontFamily(tag: tag)

        setHTML(html)
        updatePlaceholderVisibility()
        refreshTypingAttributesAndPlaceholderFont()
        if let selection = contents["selection"] as? NSDictionary,
            let start = selection["start"] as? NSNumber,
            let end = selection["end"]  as? NSNumber {
            setSelection(start: start, end: end)
        }
        // This signals the RN/JS system that the component needs to relayout
        setNeedsLayout()
    }

    override var textColor: UIColor? {
        didSet {
            typingAttributes[NSAttributedString.Key.foregroundColor] = self.textColor
            self.defaultTextColor = self.textColor
        }
    }

    override var typingAttributes: [NSAttributedString.Key : Any] {
        didSet {
            // Keep placeholder attributes in sync with typing attributes.
            placeholderLabel.attributedText = NSAttributedString(string: placeholderLabel.text ?? "", attributes: placeholderAttributes)
        }
    }

    // MARK: - Placeholder

    @objc var placeholder: String {
        set {
            placeholderLabel.attributedText = NSAttributedString(string: newValue, attributes: placeholderAttributes)
        }

        get {
            return placeholderLabel.text ?? ""
        }
    }

    /// Attributes to use on the placeholder.
    var placeholderAttributes: [NSAttributedString.Key: Any] {
        var placeholderAttributes = typingAttributes
        placeholderAttributes[.foregroundColor] = placeholderTextColor
        return placeholderAttributes
    }

    @objc var placeholderTextColor: UIColor {
        set {
            placeholderLabel.textColor = newValue
        }
        get {
            return placeholderLabel.textColor
        }
    }

    var linkTextColor: UIColor {
        set {
            let shadow = NSShadow()
            shadow.shadowColor = newValue
            linkTextAttributes = [.foregroundColor: newValue, .underlineStyle: NSNumber(value: NSUnderlineStyle.single.rawValue), .shadow: shadow]
        }
        get {
            return linkTextAttributes[.foregroundColor] as? UIColor ?? UIColor.blue
        }
    }

    func setSelection(start: NSNumber, end: NSNumber) {
        if let startPosition = position(from: beginningOfDocument, offset: start.intValue),
            let endPosition = position(from: beginningOfDocument, offset: end.intValue) {
            selectedTextRange = textRange(from: startPosition, to: endPosition)
        }
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !self.text.replacingOccurrences(of: String(.zeroWidthSpace), with: "").isEmpty
    }

    // MARK: - Font Setters

    @objc func setFontFamily(_ family: String) {
        guard fontFamily != family else {
            return
        }
        fontFamily = family
        refreshFont()
    }

    @objc func setFontSize(_ size: CGFloat) {
        guard fontSize != size else {
            return
        }
        fontSize = size
        refreshFont()
        refreshLineHeight()
    }

    @objc func setFontWeight(_ weight: String) {
        guard fontWeight != weight else {
            return
        }
        fontWeight = weight
        refreshFont()
    }

    @objc func setLineHeight(_ newLineHeight: CGFloat) {
        guard lineHeight != newLineHeight else {
            return
        }
        lineHeight = newLineHeight
        refreshLineHeight()
    }

    // MARK: - Font Refreshing

    /// Applies the family, size and weight constraints to the provided font.
    ///
    private func applyFontConstraints(to baseFont: UIFont) -> UIFont {
        let oldDescriptor = baseFont.fontDescriptor
        let newFontSize: CGFloat

        if let fontSize = fontSize {
            newFontSize = fontSize
        } else {
            newFontSize = baseFont.pointSize
        }

        var newTraits = oldDescriptor.symbolicTraits

        if let fontWeight = fontWeight {
            if (fontWeight == "bold") {
                newTraits.update(with: .traitBold)
            }
        }

        var newDescriptor: UIFontDescriptor

        if let fontFamily = fontFamily {
            newDescriptor = UIFontDescriptor(name: fontFamily, size: newFontSize)
            newDescriptor = newDescriptor.withSymbolicTraits(newTraits) ?? newDescriptor
        } else {
            newDescriptor = oldDescriptor
        }

        return UIFont(descriptor: newDescriptor, size: newFontSize)
    }

    /// Returns the font from the specified attributes, or the default font if no specific one is set.
    ///
    private func font(from attributes: [NSAttributedString.Key: Any]) -> UIFont {
        return attributes[.font] as? UIFont ?? defaultFont
    }

    /// This method refreshes the font for the whole view if the font-family, the font-size or the font-weight
    /// were ever set.
    ///
    private func refreshFont() {
        let newFont = applyFontConstraints(to: defaultFont)
        defaultFont = newFont
    }

    /// This method refreshes the font for the palceholder field and typing attributes.
    /// This method should not be called directly.  Call `refreshFont()` instead.
    ///
    private func refreshTypingAttributesAndPlaceholderFont() {
        let currentFont = font(from: typingAttributes)
        placeholderLabel.font = currentFont
    }

    /// This method refreshes the line height.
    private func refreshLineHeight() {
        if let lineHeight = lineHeight {
            let attributeString = NSMutableAttributedString(string: self.text)
            let style = NSMutableParagraphStyle()
            let currentFontSize = fontSize ?? defaultFont.pointSize
            let lineSpacing = ((currentFontSize * lineHeight)) - (currentFontSize / lineHeight) / 2

            style.lineSpacing = lineSpacing
            defaultParagraphStyle.regularLineSpacing = lineSpacing
            textStorage.addAttribute(NSAttributedString.Key.paragraphStyle, value: style, range: NSMakeRange(0, textStorage.length))
        }
    }

    /// This method sets the desired font family
    /// for specific tags.
    private func checkDefaultFontFamily(tag: String) {
        // Since we are using the defaultFont to customize
        // the font size, we need to set the monospace font.
        if (blockUseDefaultFont && tag == "pre") {
            setFontFamily(FontProvider.shared.monospaceFont.fontName)
        }
    }

    // MARK: - Formatting interface

    @objc func toggleFormat(format: String) {
        let emptyRange = NSRange(location: selectedRange.location, length: 0)
        switch format {
        case "bold": toggleBold(range: emptyRange)
        case "italic": toggleItalic(range: emptyRange)
        case "strikethrough": toggleStrikethrough(range: emptyRange)
        case "mark": toggleMark(range: emptyRange)
        default: print("Format not recognized")
        }
    }

    @objc func toggleSelectedFormat(format: String) {
        let range = selectedRange
        let emptyRange = NSRange(location: selectedRange.location, length: 0)
        switch format {
            case "bold": toggleBold(range: range)
            case "italic": toggleItalic(range: range)
            case "strikethrough": toggleStrikethrough(range: range)
            case "mark": toggleMark(range: range)
            //todo: need found better place for history manager
            case "undo": do {
                self.undoManager?.undo()
            }
            case "redo": do {
                self.undoManager?.redo()
            }
            case "hr": do {
              replaceWithHorizontalRuler(at: emptyRange)
              insertText(" ")
            }
            case "photo": do {
              showImagePicker()
            }
            default: print("Format not recognized")
        }
    }


    // MARK: - Event Propagation

    func propagateContentChanges() {
        if let onChange = onChange {
            let text = packForRN(cleanHTML(), withName: "text")
            onChange(text)
        }
    }
    func propagateFormatChanges() {
        guard let onActiveFormatsChange = onActiveFormatsChange else {
            return
        }
        let identifiers: Set<FormattingIdentifier>
        if selectedRange.length > 0 {
            identifiers = formattingIdentifiersSpanningRange(selectedRange)
        } else {
            identifiers = formattingIdentifiersForTypingAttributes()
        }
        let formats = identifiers.compactMap { formatStringMap[$0] }
        onActiveFormatsChange(["formats": formats])
    }
    func propagateSelectionChanges() {
        guard let onSelectionChange = onSelectionChange else {
            return
        }
        let caretData = packCaretDataForRN()
        onSelectionChange(caretData)
    }

    // MARK: - Selection
    private func correctSelectionAfterLastEmptyLine() {
        guard selectedTextRange?.start == endOfDocument,
            let characterToReplaceLastEmptyLine = storage.htmlConverter.characterToReplaceLastEmptyLine,
            text == String(characterToReplaceLastEmptyLine) else {
            return
        }
        selectedTextRange = self.textRange(from: beginningOfDocument, to: beginningOfDocument)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard isFirstResponder, isInsertingDictationResult == false else {
            return
        }

        correctSelectionAfterLastEmptyLine()
        propagateSelectionChanges()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        correctSelectionAfterLastEmptyLine()
    }

    func textViewDidChange(_ textView: UITextView) {
        guard isInsertingDictationResult == false else {
            return
        }

        propagateContentChanges()
        updatePlaceholderVisibility()
        propagateFormatChanges()
        //Necessary to send height information to JS after pasting text.
        textView.setNeedsLayout()
    }

    override func becomeFirstResponder() -> Bool {
        if !isFirstResponder && canBecomeFirstResponder {
            onFocus?([:])
        }
        return super.becomeFirstResponder()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        let text = packForRN(cleanHTML(), withName: "text")
        onBlur?(text)
    }

    @objc func showImagePicker() {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary) ?? []
        picker.delegate = self
        picker.allowsEditing = false
        picker.navigationBar.isTranslucent = false
        picker.modalPresentationStyle = .currentContext
        let presentedViewController = RCTPresentedViewController();
        presentedViewController!.present(picker, animated: true, completion: nil)
    }
}
class MediaInserter
{
    fileprivate var mediaErrorMode = false

    struct MediaProgressKey {
        static let mediaID = ProgressUserInfoKey("mediaID")
        static let videoURL = ProgressUserInfoKey("videoURL")
    }

    let richTextView: RCTAztecView

    var attachmentTextAttributes: [NSAttributedString.Key: Any]

    init(textView: RCTAztecView, attachmentTextAttributes: [NSAttributedString.Key: Any]) {
        self.richTextView = textView
        self.attachmentTextAttributes = attachmentTextAttributes
    }

    func insertImage(_ image: UIImage, imageUrl: NSString?, headers: NSDictionary?, parameters: NSDictionary?) {

        let fileURL = image.saveToTemporaryFile()
        let attachment = richTextView.replaceWithImage(at: richTextView.selectedRange, sourceURL: fileURL, placeHolderImage: image)
        attachment.size = .full
        attachment.alignment = ImageAttachment.Alignment.center

        image.uploadToRemoteServer(richTextView: richTextView, attachment: attachment, imageUrl: imageUrl!, headers: headers, parameters: parameters)
        let imageID = attachment.identifier
        let progress = Progress(parent: nil, userInfo: [MediaProgressKey.mediaID: imageID])
        progress.totalUnitCount = 100

        Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(MediaInserter.timerFireMethod(_:)), userInfo: progress, repeats: true)
    }

    func insertVideo(_ videoURL: URL) {
        let asset = AVURLAsset(url: videoURL, options: nil)
        let imgGenerator = AVAssetImageGenerator(asset: asset)
        imgGenerator.appliesPreferredTrackTransform = true
        guard let cgImage = try? imgGenerator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil) else {
            return
        }
        let posterImage = UIImage(cgImage: cgImage)
        let posterURL = posterImage.saveToTemporaryFile()
        let attachment = richTextView.replaceWithVideo(at: richTextView.selectedRange, sourceURL: URL(string:"placeholder://")!, posterURL: posterURL, placeHolderImage: posterImage)
        let mediaID = attachment.identifier
        let progress = Progress(parent: nil, userInfo: [MediaProgressKey.mediaID: mediaID, MediaProgressKey.videoURL:videoURL])
        progress.totalUnitCount = 100

        Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(MediaInserter.timerFireMethod(_:)), userInfo: progress, repeats: true)
    }


    @objc func timerFireMethod(_ timer: Timer) {
        guard let progress = timer.userInfo as? Progress,
              let imageId = progress.userInfo[MediaProgressKey.mediaID] as? String,
              let attachment = richTextView.attachment(withId: imageId)
        else {
            timer.invalidate()
            return
        }
        progress.completedUnitCount += 1

        attachment.progress = progress.fractionCompleted
        if mediaErrorMode && progress.fractionCompleted >= 0.25 {
            timer.invalidate()
            let message = NSAttributedString(string: "Upload failed!", attributes: attachmentTextAttributes)
            attachment.message = message
            if #available(iOS 13.0, *) {
                attachment.overlayImage = UIImage(systemName: "arrow.clockwise")
            } else {
                // Fallback on earlier versions
            }
        }
        if progress.fractionCompleted >= 1 {
            timer.invalidate()
            self.richTextView.updateContentSizeInRN()
            attachment.progress = nil
            if let videoAttachment = attachment as? VideoAttachment, let videoURL = progress.userInfo[MediaProgressKey.videoURL] as? URL {
                videoAttachment.updateURL(videoURL, refreshAsset: false)
            }
        }
        richTextView.refresh(attachment, overlayUpdateOnly: true)
    }

}
struct Response: Decodable {
    let url: URL
    let id: Int
}
extension UIImage {

    func saveToTemporaryFile() -> URL {
        let fileName = "\(ProcessInfo.processInfo.globallyUniqueString)_file.jpg"

        guard let data = self.jpegData(compressionQuality: 0.9) else {
            fatalError("Could not conert image to JPEG.")
        }

        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)

        guard (try? data.write(to: fileURL, options: [.atomic])) != nil else {
            fatalError("Could not write the image to disk.")
        }

        return fileURL
    }


    func uploadToRemoteServer(richTextView: RCTAztecView, attachment: ImageAttachment, imageUrl: NSString, headers: NSDictionary?, parameters: NSDictionary?) {
        let url = URL(string: imageUrl as String)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        for (key,value) in headers! {
            request.setValue(value as! String, forHTTPHeaderField: key as! String)
        }
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let fileName = "\(ProcessInfo.processInfo.globallyUniqueString)_file.jpg"
        guard let data = self.jpegData(compressionQuality: 0.5) else {
            fatalError("Could not conert image to JPEG.")
        }
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"story_image[image]\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        for (key, value) in parameters! {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"story_image[\(key)]\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if((error) != nil) {
                attachment.updateURL(nil)
                //todo: uploadImage Error event here
                return
            }
            let str = String(data: data!, encoding: String.Encoding.utf8)
            let resp: Response = try! JSONDecoder().decode(Response.self, from: data!)

            DispatchQueue.main.async {
                if let attachmentRange = richTextView.textStorage.ranges(forAttachment: attachment).first {
                    richTextView.setLink(resp.url, inRange: attachmentRange)

                }
                attachment.extraAttributes["data-image_id"] = .string("\(resp.id)")
                attachment.extraAttributes["loading"] = .string("true")
                attachment.extraAttributes["react"] = .string("true")
                attachment.updateURL(resp.url)
                richTextView.insertText("\n")
                richTextView.updateContentSizeInRN()
            }

        }
        task.resume()
    }
}
// MARK: UITextView Delegate Methods
//extension RCTAztecView: UITextViewDelegate {
//
//    func textViewDidChangeSelection(_ textView: UITextView) {
//        guard isFirstResponder, isInsertingDictationResult == false else {
//            return
//        }
//
//        correctSelectionAfterLastEmptyLine()
//        propagateSelectionChanges()
//    }
//
//    func textViewDidBeginEditing(_ textView: UITextView) {
//        correctSelectionAfterLastEmptyLine()
//    }
//
//    func textViewDidChange(_ textView: UITextView) {
//        guard isInsertingDictationResult == false else {
//            return
//        }
//
//        propagateContentChanges()
//        updatePlaceholderVisibility()
//        //Necessary to send height information to JS after pasting text.
//        textView.setNeedsLayout()
//    }
//
//    override func becomeFirstResponder() -> Bool {
//        if !isFirstResponder && canBecomeFirstResponder {
//            onFocus?([:])
//        }
//        return super.becomeFirstResponder()
//    }
//
//    func textViewDidEndEditing(_ textView: UITextView) {
//        let text = packForRN(cleanHTML(), withName: "text")
//        onBlur?(text)
//    }
//}
