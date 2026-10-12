@{
    # Legacy Visual Studio roles often store content in a component named
    # Background. Classification here is semantic, not based on the XML
    # component name.
    OpaqueContent = @(
        @{ Role = 'AutoHideTabMouseOverText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillTertiary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'ComboBoxFocusedGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'ComboBoxFocusedBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'ComboBoxFocusedText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'ComboBoxFocusedBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'ComboBoxItemTextInactive'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'ComboBoxBackground'; Minimum = 4.5; Classification = 'inactive text' }
        @{ Role = 'ComboBoxItemMouseOverText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'ComboBoxItemMouseOverBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'ComboBoxMouseDownGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'ComboBoxMouseDownBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'ComboBoxMouseDownText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'ComboBoxMouseDownBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'ComboBoxMouseOverGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'ComboBoxMouseOverBackgroundBegin'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'ComboBoxMouseOverText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'ComboBoxMouseOverBackgroundBegin'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'CommandBarMenuGlyph'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'CommandBarMenuBackgroundGradientBegin'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'CommandBarMenuMouseDownGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillTertiary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'CommandBarMenuMouseOverGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillTertiary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'CommandBarMenuMouseOverSubmenuGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillTertiary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'CommandBarMenuScrollGlyph'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'CommandBarMenuBackgroundGradientBegin'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'CommandBarMenuSubmenuGlyph'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'CommandBarMenuBackgroundGradientBegin'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'CommandBarMenuSubmenuGlyphHover'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'CommandBarMenuItemMouseOver'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'CommandBarMenuWatermarkText'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'CommandBarMenuBackgroundGradientBegin'; Minimum = 4.5; Classification = 'secondary text' }
        @{ Role = 'CommandBarMenuWatermarkTextHover'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'CommandBarMenuItemMouseOver'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'CommandBarOptionsMouseDownGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillTertiary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'CommandBarOptionsMouseOverGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillTertiary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'CommandBarSplitButtonMouseDownGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillTertiary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'CommandBarSplitButtonMouseOverGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillTertiary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'CommandBarTextActive'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'CommandBarGradientBegin'; Minimum = 4.5; Classification = 'secondary text' }
        @{ Role = 'CommandBarTextHover'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'CommandBarMouseOverBackgroundBegin'; SurfaceBase = 'SolidBackgroundFillBase'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'CommandBarTextHoverOverSelected'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'CommandBarSelected'; SurfaceBase = 'SolidBackgroundFillBase'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'CommandBarTextInactive'; Anchor = 'TextFillDisabled'; SurfaceCategory = 'Environment'; SurfaceRole = 'CommandBarGradientBegin'; Minimum = 1.0; Classification = 'disabled text (threshold-exempt)' }
        @{ Role = 'CommandBarTextMouseDown'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'CommandBarMouseDownBackgroundBegin'; SurfaceBase = 'SolidBackgroundFillBase'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'CommandBarTextSelected'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'CommandBarSelected'; SurfaceBase = 'SolidBackgroundFillBase'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'DebuggerDataTipActiveHighlightText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'DebuggerDataTipActiveHighlight'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'DebuggerDataTipActiveText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'DebuggerDataTipActiveBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'DebuggerDataTipInactiveHighlightText'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'DebuggerDataTipInactiveHighlight'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'inactive text' }
        @{ Role = 'DebuggerDataTipInactiveText'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'DebuggerDataTipInactiveBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'inactive text' }
        @{ Role = 'DockTargetGlyphBorder'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'DockTargetGlyphBackgroundBegin'; Minimum = 3.0; Classification = 'meaningful docking outline' }
        @{ Role = 'DocWellOverflowButtonMouseDownGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'DocWellOverflowButtonMouseDownBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'DocWellOverflowButtonMouseOverGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'DocWellOverflowButtonMouseOverBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'DropDownMouseDownGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'DropDownMouseDownBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'DropDownMouseDownText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'DropDownMouseDownBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'DropDownMouseOverGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'DropDownMouseOverBackgroundBegin'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'DropDownMouseOverText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'DropDownMouseOverBackgroundBegin'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'FileTabButtonDownSelectedActiveGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabSelectedBackground'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'FileTabButtonDownSelectedInactiveGlyph'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabProvisionalSelectedInactive'; Minimum = 3.0; Classification = 'inactive glyph' }
        @{ Role = 'FileTabButtonHoverInactiveGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabButtonHoverInactive'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 3.0; Classification = 'meaningful neutral-hover glyph' }
        @{ Role = 'FileTabButtonHoverSelectedActiveGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabSelectedBackground'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'FileTabButtonHoverSelectedInactiveGlyph'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabProvisionalSelectedInactive'; Minimum = 3.0; Classification = 'inactive glyph' }
        @{ Role = 'FileTabButtonProvisionalDownInactiveGlyph'; Anchor = 'TextOnAccentFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabButtonProvisionalDownInactive'; Minimum = 3.0; Classification = 'meaningful on-accent glyph' }
        @{ Role = 'FileTabButtonProvisionalDownSelectedActiveGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabProvisionalSelectedActive'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'FileTabButtonProvisionalDownSelectedInactiveGlyph'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabProvisionalSelectedInactive'; Minimum = 3.0; Classification = 'inactive glyph' }
        @{ Role = 'FileTabButtonProvisionalHoverInactiveGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabButtonProvisionalHoverInactive'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 3.0; Classification = 'meaningful neutral-hover glyph' }
        @{ Role = 'FileTabButtonProvisionalHoverSelectedActiveGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabProvisionalSelectedActive'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'FileTabButtonProvisionalHoverSelectedInactiveGlyph'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabProvisionalSelectedInactive'; Minimum = 3.0; Classification = 'inactive glyph' }
        @{ Role = 'FileTabButtonProvisionalHoverGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabProvisionalHover'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'FileTabButtonProvisionalSelectedActiveGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabProvisionalSelectedActive'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'FileTabButtonProvisionalSelectedInactiveGlyph'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabProvisionalSelectedInactive'; Minimum = 3.0; Classification = 'inactive glyph' }
        @{ Role = 'FileTabButtonSelectedActiveGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabSelectedBackground'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'FileTabButtonSelectedInactiveGlyph'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabProvisionalSelectedInactive'; Minimum = 3.0; Classification = 'inactive glyph' }
        @{ Role = 'FileTabIndicatorTextSelectedActive'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabSelectedBackground'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'FileTabIndicatorTextSelectedInactive'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabProvisionalSelectedInactive'; Minimum = 4.5; Classification = 'inactive text' }
        @{ Role = 'FileTabLastActiveGlyph'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabLastActiveGradientTop'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'FileTabLastActiveText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabLastActiveGradientTop'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'FileTabProvisionalHoverForeground'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabProvisionalHover'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'FileTabProvisionalSelectedActiveForeground'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabProvisionalSelectedActive'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'FileTabProvisionalSelectedInactiveForeground'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabProvisionalSelectedInactive'; Minimum = 4.5; Classification = 'inactive text' }
        @{ Role = 'FileTabScrollBarArrowGlyphHover'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabBackground'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'FileTabScrollBarArrowGlyphPressed'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabBackground'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'FileTabSelectedText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'FileTabSelectedBackground'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'HelpSearchProviderSelectedText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'HelpSearchProviderSelectedBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'HelpSearchProviderUnselectedText'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'HelpSearchProviderUnselectedBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'inactive text' }
        @{ Role = 'HelpSearchResultSelectedText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'HelpSearchResultSelectedBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'InactiveCaptionText'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'TitleBarInactive'; Minimum = 4.5; Classification = 'inactive text' }
        @{ Role = 'MainWindowButtonDownGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'MainWindowButtonDown'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'MainWindowButtonHoverActiveGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'MainWindowButtonHoverActive'; SurfaceBase = 'SolidBackgroundFillBase'; Minimum = 3.0; Classification = 'meaningful neutral-hover glyph' }
        @{ Role = 'MainWindowButtonHoverInactiveGlyph'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'MainWindowButtonHoverInactive'; SurfaceBase = 'SolidBackgroundFillBase'; Minimum = 3.0; Classification = 'inactive neutral-hover glyph' }
        @{ Role = 'MainWindowResizeGripTexture1'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillBase'; Minimum = 3.0; Classification = 'meaningful resize indicator' }
        @{ Role = 'MainWindowResizeGripTexture2'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillBase'; Minimum = 3.0; Classification = 'meaningful resize indicator' }
        @{ Role = 'MainWindowSolutionNameActiveText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'TitleBarActive'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'MainWindowSolutionNameInactiveText'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'TitleBarInactive'; Minimum = 4.5; Classification = 'inactive text' }
        @{ Role = 'NewProjectProviderHoverForeground'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'NewProjectProviderHoverBegin'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'NewProjectProviderInactiveForeground'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'NewProjectProviderInactiveBegin'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'inactive text' }
        @{ Role = 'QuickCustomizeButtonGlyphHover'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'QuickCustomizeButton'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'QuickCustomizeButtonTextHover'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'QuickCustomizeButton'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'RaftedWindowButtonDownGlyph'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'RaftedWindowButtonDown'; Minimum = 3.0; Classification = 'meaningful glyph' }
        @{ Role = 'ScrollBarThumbGlyphPressedBorder'; Anchor = 'TextFillTertiary'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillSecondary'; Minimum = 3.0; Classification = 'meaningful pressed outline' }
        @{ Role = 'SmartTagHoverText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'SmartTagHoverFill'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'StartPageButtonTextHover'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'StartPageButtonMouseOverBackgroundBegin'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'StartPageTextBody'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'StartPageBackgroundGradientBegin'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'StartPageTextBodySelected'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'StartPageSelectedItemBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'StartPageTextBodyUnselected'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'StartPageUnselectedItemBackgroundBegin'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'StartPageTextHeadingMouseOver'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'StartPageUnselectedItemBackgroundBegin'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'StartPageTextHeadingSelected'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'StartPageSelectedItemBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'StartPageTextSubHeadingMouseOver'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'StartPageUnselectedItemBackgroundBegin'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'StartPageTextSubHeadingSelected'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'StartPageSelectedItemBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'TitleBarActiveText'; Anchor = 'TextFillPrimary'; SurfaceCategory = 'Environment'; SurfaceRole = 'TitleBarActive'; Minimum = 4.5; Classification = 'normal text' }
        @{ Role = 'TitleBarInactiveText'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'TitleBarInactive'; Minimum = 4.5; Classification = 'inactive text' }
        @{ Role = 'ToolTipHintText'; Anchor = 'TextFillSecondary'; SurfaceCategory = 'Environment'; SurfaceRole = 'ToolTip'; Minimum = 4.5; Classification = 'secondary text' }
    )

    SurfaceRoles = @(
        @{ Role = 'ActiveCaption'; AnchorCategory = 'Environment'; Anchor = 'TitleBarActive'; Classification = 'active caption surface' }
        @{ Role = 'InactiveCaption'; AnchorCategory = 'Environment'; Anchor = 'TitleBarInactive'; Classification = 'inactive caption surface' }
        @{ Role = 'MainWindowActiveCaption'; AnchorCategory = 'Environment'; Anchor = 'TitleBarActive'; Classification = 'active main-window surface' }
        @{ Role = 'MainWindowInactiveCaption'; AnchorCategory = 'Environment'; Anchor = 'TitleBarInactive'; Classification = 'inactive main-window surface' }
        @{ Role = 'FileTabDocumentBorderBackground'; AnchorCategory = 'Environment'; Anchor = 'FileTabSelectedBorder'; Classification = 'active document border' }
        @{ Role = 'FileTabDocumentBorderHighlight'; AnchorCategory = 'Environment'; Anchor = 'FileTabSelectedBorder'; Classification = 'active document border highlight' }
        @{ Role = 'FileTabLastActiveGradientBottom'; AnchorCategory = 'Shell'; Anchor = 'SolidBackgroundFillSecondary'; Classification = 'last-active tab surface' }
        @{ Role = 'FileTabLastActiveGradientMiddle1'; AnchorCategory = 'Shell'; Anchor = 'SolidBackgroundFillSecondary'; Classification = 'last-active tab surface' }
        @{ Role = 'FileTabLastActiveGradientMiddle2'; AnchorCategory = 'Shell'; Anchor = 'SolidBackgroundFillSecondary'; Classification = 'last-active tab surface' }
        @{ Role = 'FileTabLastActiveGradientTop'; AnchorCategory = 'Shell'; Anchor = 'SolidBackgroundFillSecondary'; Classification = 'last-active tab surface' }
        @{ Role = 'FileTabProvisionalSelectedActive'; AnchorCategory = 'Shell'; Anchor = 'SolidBackgroundFillSenary'; Classification = 'selected provisional tab surface' }
        @{ Role = 'FileTabProvisionalSelectedActiveBorder'; AnchorCategory = 'Environment'; Anchor = 'FileTabSelectedBorder'; Classification = 'selected provisional tab border' }
        @{ Role = 'FileTabProvisionalSelectedInactive'; AnchorCategory = 'Shell'; Anchor = 'SolidBackgroundFillSecondary'; Classification = 'inactive provisional tab surface' }
        @{ Role = 'FileTabSelectedBackground'; AnchorCategory = 'Shell'; Anchor = 'SolidBackgroundFillSenary'; Classification = 'selected document tab surface' }
        @{ Role = 'FileTabSelectedGradientBottom'; AnchorCategory = 'Shell'; Anchor = 'SolidBackgroundFillSenary'; Classification = 'selected document tab surface' }
        @{ Role = 'FileTabSelectedGradientMiddle1'; AnchorCategory = 'Shell'; Anchor = 'SolidBackgroundFillSenary'; Classification = 'selected document tab surface' }
        @{ Role = 'FileTabSelectedGradientMiddle2'; AnchorCategory = 'Shell'; Anchor = 'SolidBackgroundFillSenary'; Classification = 'selected document tab surface' }
        @{ Role = 'FileTabSelectedGradientTop'; AnchorCategory = 'Shell'; Anchor = 'SolidBackgroundFillSenary'; Classification = 'selected document tab surface' }
    )

    EnabledLinks = @(
        'CommandBarMenuGroupHeaderLinkText'
        'CommandBarMenuGroupHeaderLinkTextHover'
        'CommandBarMenuLinkText'
        'CommandBarMenuLinkTextHover'
        'CommandBarMenuWatermarkLinkText'
        'CommandBarMenuWatermarkLinkTextHover'
        'ControlLinkText'
        'ControlLinkTextHover'
        'ControlLinkTextPressed'
        'DiagReportLinkText'
        'DiagReportLinkTextHover'
        'EditorExpansionLink'
        'HelpHowDoIPaneLink'
        'HelpHowDoITaskLink'
        'HelpSearchResultLinkSelected'
        'HelpSearchResultLinkUnselected'
        'PanelHyperlink'
        'PanelHyperlinkHover'
        'PanelHyperlinkPressed'
        'StartPageTextControlLinkSelected'
        'StartPageTextControlLinkSelectedHover'
    )

    SelectionLinks = @(
        @{ Role = 'PanelHyperlinkInsideSelection'; ForegroundAnchor = 'TextOnAccentFillSelectedText'; Minimum = 4.5 }
        @{ Role = 'PanelHyperlinkInsideSelectionActive'; ForegroundAnchor = 'TextOnAccentFillSelectedText'; BackgroundAnchor = 'AccentFillSelectedTextBackground'; Minimum = 4.5 }
        @{ Role = 'PanelHyperlinkInsideSelectionInactive'; ForegroundAnchor = 'HyperlinkFillPrimary'; BackgroundAnchor = 'AccentFillSenary'; BackgroundBase = 'SolidBackgroundFillSecondary'; Minimum = 4.5 }
    )

    DisabledRoles = @(
        @{ Role = 'PanelHyperlinkDisabled'; Component = 'Background'; Anchor = 'HyperlinkFillDisabled'; AdvisoryMinimum = 1.5; Reason = 'Disabled hyperlink remains advisory and threshold-exempt.' }
        @{ Role = 'PanelDisabledHyperlinkInsideSelectionActive'; Component = 'Foreground'; Anchor = 'TextOnAccentFillPrimary'; Alpha = '80'; AdvisoryMinimum = 1.5; Reason = 'Disabled text on an active accent selection uses a translucent dark on-accent foreground.' }
        @{ Role = 'PanelDisabledHyperlinkInsideSelectionInactive'; Component = 'Foreground'; Anchor = 'HyperlinkFillDisabled'; AdvisoryMinimum = 1.5; Reason = 'Disabled selected hyperlink remains advisory and threshold-exempt.' }
    )

    SemanticBorders = @(
        @{ Role = 'ToolWindowValidationErrorBorder'; Anchor = 'SystemFillCritical'; Classification = 'critical validation indicator' }
        @{ Role = 'ScreenTipBorder'; Anchor = 'SystemFillCaution'; Classification = 'caution emphasis indicator' }
        @{ Role = 'SmartTagBorder'; Anchor = 'SystemFillCaution'; Classification = 'caution emphasis indicator' }
        @{ Role = 'CommandBarMouseDownBorder'; Anchor = 'AccentFillDefault'; Classification = 'pressed command indicator' }
        @{ Role = 'CommandBarSelectedBorder'; Anchor = 'AccentFillDefault'; Classification = 'selected command indicator' }
    )

    StatePairs = @(
        @{ Active = 'TitleBarActiveText'; Inactive = 'TitleBarInactiveText'; Reason = 'Active and inactive title text must remain distinguishable.' }
        @{ Active = 'MainWindowSolutionNameActiveText'; Inactive = 'MainWindowSolutionNameInactiveText'; Reason = 'Active and inactive solution-name text must remain distinguishable.' }
        @{ Active = 'HelpSearchProviderSelectedText'; Inactive = 'HelpSearchProviderUnselectedText'; Reason = 'Selected and unselected providers must remain distinguishable.' }
        @{ Active = 'DebuggerDataTipActiveText'; Inactive = 'DebuggerDataTipInactiveText'; Reason = 'Active and inactive debugger DataTips must remain distinguishable.' }
        @{ Active = 'NewProjectProviderHoverForeground'; Inactive = 'NewProjectProviderInactiveForeground'; Reason = 'Hovered and inactive providers must remain distinguishable.' }
    )

    # Modern controls use the installed Dark alpha hierarchy while substituting
    # each theme's palette-neutral text ramps for literal white.
    NeutralModernTokens = @(
        @{ Role = 'ControlFillDefault'; Anchor = 'TextFillPrimary'; Alpha = '0F'; Classification = 'resting neutral control fill' }
        @{ Role = 'ControlFillSecondary'; Anchor = 'TextFillPrimary'; Alpha = '15'; Classification = 'secondary neutral control fill' }
        @{ Role = 'ControlFillTertiary'; Anchor = 'TextFillPrimary'; Alpha = '08'; Classification = 'tertiary neutral control fill' }
        @{ Role = 'ControlFillQuaternary'; Anchor = 'TextFillPrimary'; Alpha = '0F'; Classification = 'quaternary neutral control fill' }
        @{ Role = 'SubtleFillSecondary'; Anchor = 'TextFillPrimary'; Alpha = '0F'; Classification = 'subtle neutral hover fill' }
        @{ Role = 'SubtleFillTertiary'; Anchor = 'TextFillPrimary'; Alpha = '0B'; Classification = 'subtle neutral pressed fill' }
        @{ Role = 'CardBackgroundFillDefault'; Anchor = 'TextFillPrimary'; Alpha = '0F'; Classification = 'resting neutral card fill' }
        @{ Role = 'CardBackgroundFillSecondary'; Anchor = 'TextFillPrimary'; Alpha = '15'; Classification = 'secondary neutral card fill' }
        @{ Role = 'CardBackgroundFillTertiary'; Anchor = 'TextFillPrimary'; Alpha = '08'; Classification = 'tertiary neutral card fill' }
        @{ Role = 'CardStrokeDefault'; Literal = '1A000000'; Classification = 'quiet dark-neutral card stroke' }
        @{ Role = 'ControlStrokeDefault'; Anchor = 'TextFillPrimary'; Alpha = '12'; Classification = 'quiet neutral control stroke' }
        @{ Role = 'ControlStrokeSecondary'; Anchor = 'TextFillPrimary'; Alpha = '12'; Classification = 'secondary neutral control stroke' }
        @{ Role = 'SurfaceStrokeDefault'; Anchor = 'TextFillSecondary'; Alpha = '66'; Classification = 'strong neutral surface stroke' }
    )

    # Representative legacy pairs validate the shared neutral state system.
    # The full named-role registry below prevents accent leakage into every
    # remediated generic surface and stroke.
    InteractionStatePairs = @(
        @{
            Name = 'combo-box hover/pressed'
            SurfaceBase = 'ComboBoxBackground'
            HoverSurface = 'ComboBoxMouseOverBackgroundBegin'
            PressedSurface = 'ComboBoxMouseDownBackground'
            HoverBorder = 'ComboBoxMouseOverBorder'
            PressedBorder = 'ComboBoxMouseDownBorder'
            HoverSurfaceAnchor = 'TextFillPrimary'
            HoverSurfaceAlpha = '18'
            PressedSurfaceLiteral = '33000000'
            HoverBorderAnchor = 'TextFillSecondary'
            HoverBorderAlpha = '66'
            PressedBorderAnchor = 'ControlStrongStrokeDefault'
            RequireSurfaceDifference = $true
            RequireBorderDifference = $true
        }
        @{
            Name = 'drop-down hover/pressed'
            SurfaceBase = 'DropDownBackground'
            HoverSurface = 'DropDownMouseOverBackgroundBegin'
            PressedSurface = 'DropDownMouseDownBackground'
            HoverBorder = 'DropDownMouseOverBorder'
            PressedBorder = 'DropDownMouseDownBorder'
            HoverSurfaceAnchor = 'TextFillPrimary'
            HoverSurfaceAlpha = '18'
            PressedSurfaceLiteral = '33000000'
            HoverBorderAnchor = 'TextFillSecondary'
            HoverBorderAlpha = '66'
            PressedBorderAnchor = 'ControlStrongStrokeDefault'
            RequireSurfaceDifference = $true
            RequireBorderDifference = $true
        }
    )

    NeutralInteractionGroups = @(
        @{
            Name = 'environment neutral hover surfaces'
            Category = 'Environment'
            Component = 'Background'
            Anchor = 'TextFillPrimary'
            Alpha = '18'
            Roles = @(
                'ComboBoxItemMouseOverBackground', 'ComboBoxMouseOverBackgroundBegin', 'ComboBoxMouseOverBackgroundEnd',
                'ComboBoxMouseOverBackgroundMiddle1', 'ComboBoxMouseOverBackgroundMiddle2', 'CommandBarCheckBoxMouseOver',
                'CommandBarFrameControlHover', 'CommandBarHover', 'CommandBarHoverOverSelected',
                'CommandBarHoverOverSelectedIcon', 'CommandBarMenuItemMouseOver', 'CommandBarMouseOverBackgroundBegin',
                'CommandBarMouseOverBackgroundEnd', 'CommandBarMouseOverBackgroundMiddle1', 'CommandBarMouseOverBackgroundMiddle2',
                'CommandBarMouseOverUnfocused', 'CommandBarOptionsMouseOverBackgroundBegin',
                'CommandBarOptionsMouseOverBackgroundEnd', 'CommandBarOptionsMouseOverBackgroundMiddle1',
                'CommandBarOptionsMouseOverBackgroundMiddle2', 'DocWellOverflowButtonMouseOverBackground',
                'DropDownButtonMouseOverBackground', 'DropDownMouseOverBackgroundBegin', 'DropDownMouseOverBackgroundEnd',
                'DropDownMouseOverBackgroundMiddle1', 'DropDownMouseOverBackgroundMiddle2', 'FileTabButtonHoverInactive',
                'FileTabButtonProvisionalHoverInactive', 'FileTabProvisionalHover', 'FileTabScrollBarThumbHover',
                'MainWindowButtonHoverActive', 'MainWindowButtonHoverInactive', 'NewProjectProviderHoverBegin',
                'NewProjectProviderHoverEnd', 'NewProjectProviderHoverMiddle1', 'NewProjectProviderHoverMiddle2',
                'PageSideBarExpanderHeaderHover', 'PanelHoverOverCloseFill', 'RaftedWindowButtonHoverActive',
                'RaftedWindowButtonHoverInactive', 'ScrollBarArrowMouseOverBackground',
                'SearchBoxMouseOverBackgroundBegin', 'SearchBoxMouseOverBackgroundEnd',
                'SearchBoxMouseOverBackgroundMiddle1', 'SearchBoxMouseOverBackgroundMiddle2', 'SmartTagHoverFill',
                'StartPageButtonMouseOverBackgroundBegin', 'StartPageButtonMouseOverBackgroundEnd',
                'StartPageButtonMouseOverBackgroundMiddle1', 'StartPageButtonMouseOverBackgroundMiddle2',
                'StartPageButtonPinHover', 'StartPageTabMouseOverBackgroundBegin', 'StartPageTabMouseOverBackgroundEnd',
                'ToolboxContentMouseOver', 'ToolWindowButtonHoverActive', 'ToolWindowButtonHoverInactive'
            )
        }
        @{
            Name = 'environment neutral pressed surfaces'
            Category = 'Environment'
            Component = 'Background'
            Literal = '33000000'
            Roles = @(
                'ComboBoxMouseDownBackground', 'CommandBarMouseDownBackgroundBegin', 'CommandBarMouseDownBackgroundEnd',
                'CommandBarMouseDownBackgroundMiddle', 'CommandBarOptionsMouseDownBackgroundBegin',
                'CommandBarOptionsMouseDownBackgroundEnd', 'CommandBarOptionsMouseDownBackgroundMiddle',
                'DocWellOverflowButtonMouseDownBackground', 'DropDownButtonMouseDownBackground',
                'DropDownMouseDownBackground', 'FileTabScrollBarThumbPressed', 'PageSideBarExpanderHeaderPressed',
                'ScrollBarArrowPressedBackground', 'SearchBoxPressedBackground'
            )
        }
        @{
            Name = 'environment neutral hover strokes'
            Category = 'Environment'
            Component = 'Background'
            Anchor = 'TextFillSecondary'
            Alpha = '66'
            Roles = @(
                'ComboBoxItemMouseOverBorder', 'ComboBoxMouseOverBorder', 'CommandBarMenuItemMouseOverBorder',
                'DocWellOverflowButtonMouseOverBorder', 'DropDownMouseOverBorder', 'PanelHoverOverCloseBorder',
                'RaftedWindowButtonHoverActiveBorder', 'RaftedWindowButtonHoverInactiveBorder',
                'ScrollBarThumbMouseOverBorder', 'SearchBoxMouseOverBorder', 'ToolWindowTabMouseOverBorder'
            )
        }
        @{
            Name = 'cider neutral hover surfaces'
            Category = 'Cider'
            Component = 'Background'
            Anchor = 'TextFillPrimary'
            Alpha = '18'
            Roles = @(
                'BreadcrumbButtonOnHover', 'ComboBoxMouseOver', 'CommandMouseOver', 'FloatingMenuMouseOver',
                'IconButtonMouseOver', 'InputMouseOver', 'InteractiveIconMouseOver', 'ListItemMouseOver',
                'ListItemSecondaryOnHover', 'TabItemMouseOver', 'ToggleMouseOver'
            )
        }
        @{
            Name = 'cider neutral pressed surfaces'
            Category = 'Cider'
            Component = 'Background'
            Literal = '33000000'
            Roles = @('ComboBoxButtonPressed', 'CommandPressed', 'IconButtonPressed')
        }
        @{
            Name = 'cider neutral hover strokes'
            Category = 'Cider'
            Component = 'Background'
            Anchor = 'TextFillSecondary'
            Alpha = '66'
            Roles = @(
                'ComboBoxMouseOverBorder', 'CommandMouseOverBorder', 'InputMouseOverBorder',
                'ListItemMouseOverBorder', 'TabItemMouseOverBorder', 'ToggleMouseOverBorder'
            )
        }
        @{
            Name = 'common-control neutral hover surfaces'
            Category = 'CommonControls'
            Component = 'Background'
            Anchor = 'TextFillPrimary'
            Alpha = '18'
            Roles = @('CheckBoxBackgroundHover')
        }
        @{
            Name = 'common-control neutral pressed surfaces'
            Category = 'CommonControls'
            Component = 'Background'
            Literal = '33000000'
            Roles = @('CheckBoxBackgroundPressed')
        }
        @{
            Name = 'common-control neutral hover strokes'
            Category = 'CommonControls'
            Component = 'Background'
            Anchor = 'TextFillSecondary'
            Alpha = '66'
            Roles = @(
                'ButtonBorderHover', 'CheckBoxBorderHover', 'ComboBoxBorderHover',
                'ComboBoxListItemBorderHover', 'InnerTabInactiveHoverBorder'
            )
        }
    )

    StrongNeutralBorders = @(
        @{ Category = 'Environment'; Role = 'ComboBoxMouseDownBorder'; Anchor = 'ControlStrongStrokeDefault'; Classification = 'pressed combo-box input border' }
        @{ Category = 'Environment'; Role = 'DropDownMouseDownBorder'; Anchor = 'ControlStrongStrokeDefault'; Classification = 'pressed drop-down input border' }
        @{ Category = 'Environment'; Role = 'SearchBoxPressedBorder'; Anchor = 'ControlStrongStrokeDefault'; Classification = 'pressed search input border' }
        @{ Category = 'Cider'; Role = 'ComboBoxButtonPressedBorder'; Anchor = 'ControlStrongStrokeDefault'; Classification = 'pressed Cider combo-box border' }
        @{ Category = 'CommonControls'; Role = 'ComboBoxBorderPressed'; Anchor = 'ControlStrongStrokeDefault'; Classification = 'pressed common combo-box border' }
        @{ Category = 'CommonControls'; Role = 'CheckBoxBorderPressed'; Anchor = 'ControlStrongStrokeDefault'; Classification = 'pressed common check-box border' }
    )

    FocusIndicators = @(
        @{ Category = 'Environment'; Role = 'ComboBoxFocusedBorder'; Anchor = 'FocusStrokeOuter'; SurfaceCategory = 'Environment'; SurfaceRole = 'ComboBoxFocusedBackground'; SurfaceBase = 'SolidBackgroundFillSecondary'; Classification = 'focused combo-box border' }
        @{ Category = 'CommonControls'; Role = 'ButtonBorderFocused'; Anchor = 'FocusStrokeOuter'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillSecondary'; Classification = 'focused button border' }
        @{ Category = 'CommonControls'; Role = 'CheckBoxBorderFocused'; Anchor = 'FocusStrokeOuter'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillSecondary'; Classification = 'focused check-box border' }
        @{ Category = 'CommonControls'; Role = 'ComboBoxBorderFocused'; Anchor = 'FocusStrokeOuter'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillSecondary'; Classification = 'focused combo-box border' }
        @{ Category = 'CommonControls'; Role = 'TextBoxBorderFocused'; Anchor = 'FocusStrokeOuter'; SurfaceCategory = 'Shell'; SurfaceRole = 'SolidBackgroundFillSecondary'; Classification = 'focused text-box border' }
    )

    # Core semantic syntax is registered by consumer role rather than inferred
    # from whichever RGB value a role happened to share with another role.
    # This prevents a palette edit from recoloring adornments, line numbers,
    # markers, or other unrelated consumers of the same source value.
    CoreSyntaxFamilyRoles = @{
        Plain = @(
            @{ Category = 'Text Editor Text Manager Items'; Role = 'Plain Text' }
        )
        Keyword = @(
            @{ Category = 'Text Editor Language Service Items'; Role = 'Keyword' }
        )
        String = @(
            @{ Category = 'Text Editor Language Service Items'; Role = 'String' }
        )
        Number = @(
            @{ Category = 'Text Editor Language Service Items'; Role = 'Number' }
            @{ Category = 'Text Editor MEF Items'; Role = 'VBScript Number' }
            @{ Category = 'Text Editor MEF Items'; Role = 'HTML Entity' }
        )
        Comment = @(
            @{ Category = 'Text Editor Language Service Items'; Role = 'Comment' }
            @{ Category = 'Text Editor Language Service Items'; Role = 'XML Comment' }
            @{ Category = 'Text Editor Language Service Items'; Role = 'XAML Comment' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CSS Comment' }
            @{ Category = 'Text Editor MEF Items'; Role = 'HTML Comment' }
            @{ Category = 'Text Editor MEF Items'; Role = 'regex - comment' }
            @{ Category = 'Text Editor MEF Items'; Role = 'VBScript Comment' }
            @{ Category = 'Text Editor MEF Items'; Role = 'XML Doc Comment' }
            @{ Category = 'Text Editor MEF Items'; Role = 'xml doc comment - comment' }
            @{ Category = 'Text Editor MEF Items'; Role = 'xml doc comment - text' }
            @{ Category = 'Text Editor MEF Items'; Role = 'xml literal - comment' }
        )
        Method = @(
            @{ Category = 'Text Editor MEF Items'; Role = 'method name' }
            @{ Category = 'Text Editor MEF Items'; Role = 'extension method name' }
            @{ Category = 'Text Editor MEF Items'; Role = 'Method' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppFunctionSemanticTokenFormat' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppMemberFunctionSemanticTokenFormat' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppStaticMemberFunctionSemanticTokenFormat' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppFunctionTemplateSemanticTokenFormat' }
        )
        Type = @(
            @{ Category = 'Text Editor MEF Items'; Role = 'class name' }
            @{ Category = 'Text Editor MEF Items'; Role = 'delegate name' }
            @{ Category = 'Text Editor MEF Items'; Role = 'module name' }
            @{ Category = 'Text Editor MEF Items'; Role = 'Type' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppEnumSemanticTokenFormat' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppTypeSemanticTokenFormat' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppRefTypeSemanticTokenFormat' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppValueTypeSemanticTokenFormat' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppClassTemplateSemanticTokenFormat' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppGenericTypeSemanticTokenFormat' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppNamespaceSemanticTokenFormat' }
        )
        Struct = @(
            @{ Category = 'Text Editor MEF Items'; Role = 'struct name' }
            @{ Category = 'Text Editor MEF Items'; Role = 'enum name' }
        )
        Interface = @(
            @{ Category = 'Text Editor MEF Items'; Role = 'interface name' }
            @{ Category = 'Text Editor MEF Items'; Role = 'type parameter name' }
        )
        Control = @(
            @{ Category = 'Text Editor MEF Items'; Role = 'keyword - control' }
        )
        Directive = @(
            @{ Category = 'Text Editor MEF Items'; Role = 'RazorDirective' }
            @{ Category = 'Text Editor MEF Items'; Role = 'RazorTransition' }
        )
        Variable = @(
            @{ Category = 'Text Editor MEF Items'; Role = 'local name' }
            @{ Category = 'Text Editor MEF Items'; Role = 'parameter name' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppGlobalVariableSemanticTokenFormat' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppLocalVariableSemanticTokenFormat' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppParameterSemanticTokenFormat' }
        )
        Operator = @(
            @{ Category = 'Text Editor MEF Items'; Role = 'Operator' }
            @{ Category = 'Text Editor MEF Items'; Role = 'operator - overloaded' }
            @{ Category = 'Text Editor MEF Items'; Role = 'punctuation' }
            @{ Category = 'Text Editor MEF Items'; Role = 'CppOperatorSemanticTokenFormat' }
            @{ Category = 'Text Editor MEF Items'; Role = 'VBScript Operator' }
        )
    }

    CoreSyntaxThemeAnchors = @{
        Amberroot = @{ Plain = 'FFF2ECD8'; Keyword = 'FFE0B862'; String = 'FFAFC58F'; Number = 'FFF9A05B'; Comment = 'FFB7AB93'; Method = 'FFF1D18E'; Type = 'FFCBDDB5'; Variable = 'FF91B8B5'; Operator = 'FFC9C3AF'; Struct = 'FF9FD4BF'; Interface = 'FFCAD47E'; Control = 'FFD6A5A9'; Directive = 'FFBCB5D5' }
        Aquatoxic = @{ Plain = 'FFF4FBFD'; Keyword = 'FF43CFE0'; String = 'FFE2F2B8'; Number = 'FFE7A830'; Comment = 'FFACB6B7'; Method = 'FFC0E67B'; Type = 'FFC4B5FD'; Variable = 'FF86E6EC'; Operator = 'FFD9EDF2'; Struct = 'FFB1D3EA'; Interface = 'FFD1D8AC'; Control = 'FFEFC3CD'; Directive = 'FFD9CCF9' }
        Biolume = @{ Plain = 'FFEDF5EF'; Keyword = 'FFA78BFA'; String = 'FFBEF264'; Number = 'FFFDE047'; Comment = 'FF8FA198'; Method = 'FF5EEAD4'; Type = 'FFA5F3FC'; Variable = 'FFC4B5FD'; Operator = 'FFBAC8BF'; Struct = 'FF8BD4B9'; Interface = 'FFD0DEAA'; Control = 'FFE4A6D1'; Directive = 'FFADAADC' }
        Cosmora = @{ Plain = 'FFC9C7DC'; Keyword = 'FFF472B6'; String = 'FF6EE7B7'; Number = 'FFFBBF24'; Comment = 'FFA09DB5'; Method = 'FFA78FEA'; Type = 'FF67E8F9'; Variable = 'FF9DB6FF'; Operator = 'FFC9C7DC'; Struct = 'FFACD8CC'; Interface = 'FFCBD7A3'; Control = 'FFF0A2C9'; Directive = 'FFCCB1E7' }
        'Cosmora Blueshift' = @{ Plain = 'FFC4D1EA'; Keyword = 'FFF472B6'; String = 'FF6EE7B7'; Number = 'FFFBBF24'; Comment = 'FF98AAC7'; Method = 'FF8299ED'; Type = 'FF67E8F9'; Variable = 'FF7CC8F4'; Operator = 'FFC4D1EA'; Struct = 'FFACD8CC'; Interface = 'FFCBD7A3'; Control = 'FFF0A2C9'; Directive = 'FFCCB1E7' }
        'Cosmora Redshift' = @{ Plain = 'FFEBC7B0'; Keyword = 'FFF472B6'; String = 'FF6EE7B7'; Number = 'FFFBBF24'; Comment = 'FFCC9E7F'; Method = 'FFF77952'; Type = 'FF67E8F9'; Variable = 'FFFFA08F'; Operator = 'FFEBC7B0'; Struct = 'FFACD8CC'; Interface = 'FFCBD7A3'; Control = 'FFF0A2C9'; Directive = 'FFCCB1E7' }
        'Cosmora Ultraviolet' = @{ Plain = 'FFE8C3D9'; Keyword = 'FFF472B6'; String = 'FF6EE7B7'; Number = 'FFFBBF24'; Comment = 'FFC998B4'; Method = 'FFB683F0'; Type = 'FF67E8F9'; Variable = 'FFE58FF2'; Operator = 'FFE8C3D9'; Struct = 'FFACD8CC'; Interface = 'FFCBD7A3'; Control = 'FFF0A2C9'; Directive = 'FFCCB1E7' }
        Foundation = @{ Plain = 'FFE7E7E7'; Keyword = 'FF2DD4BF'; String = 'FF86EFAC'; Number = 'FFFACC15'; Comment = 'FF9A9A9A'; Method = 'FFC4B5FD'; Type = 'FF7DD3FC'; Variable = 'FF5EEAD4'; Operator = 'FFC7C7C7'; Struct = 'FF9BCCBA'; Interface = 'FFCDD6AA'; Control = 'FFD3A1C2'; Directive = 'FFAEA0DC' }
        Hardline = @{ Plain = 'FFFAFAF7'; Keyword = 'FFFFAA2B'; String = 'FFA7D7A9'; Number = 'FFE6C785'; Comment = 'FFB6A58E'; Method = 'FFFFE066'; Type = 'FF8EC8E5'; Variable = 'FF89AABD'; Operator = 'FFC3C7C5'; Struct = 'FF80CDBE'; Interface = 'FFD6DAB4'; Control = 'FFECA099'; Directive = 'FFC2AED9' }
        Nightglass = @{ Plain = 'FFE7E7E7'; Keyword = 'FF8893F8'; String = 'FF6EE7B7'; Number = 'FFFACC15'; Comment = 'FF8FA3BF'; Method = 'FFDCA8FF'; Type = 'FF67E8F9'; Variable = 'FFA5B4FC'; Operator = 'FFB8C7DC'; Struct = 'FF95D7C5'; Interface = 'FFC8D5AE'; Control = 'FFE3A3C7'; Directive = 'FFBAA9D3' }
        Nullsector = @{ Plain = 'FFE7EEF7'; Keyword = 'FFFF4C96'; String = 'FFA7E36F'; Number = 'FFFFC857'; Comment = 'FF8593A5'; Method = 'FFC9A7FF'; Type = 'FF63E6FF'; Variable = 'FF71C4FF'; Operator = 'FF9AA7B7'; Struct = 'FF86D8B4'; Interface = 'FFCCD7A0'; Control = 'FFD999D5'; Directive = 'FFAAADE2' }
        Pinknoise = @{ Plain = 'FFF8EDF3'; Keyword = 'FFF27CAF'; String = 'FFF3B6D1'; Number = 'FFF3A56F'; Comment = 'FFA78E9B'; Method = 'FFF69BC0'; Type = 'FFB59AF7'; Variable = 'FF56D8D0'; Operator = 'FFC9B1BE'; Struct = 'FF99BDDB'; Interface = 'FFC9C1E8'; Control = 'FFDA9FE0'; Directive = 'FFAFA7D7' }
        Silverphase = @{ Plain = 'FFE7EEF8'; Keyword = 'FF978AF2'; String = 'FF7EE6F2'; Number = 'FFFACC15'; Comment = 'FF91A6C4'; Method = 'FF9CCBF2'; Type = 'FFB7A7F7'; Variable = 'FF72B5FF'; Operator = 'FFD4DCE8'; Struct = 'FF9FD1C4'; Interface = 'FFCDD7AC'; Control = 'FFDFA2CE'; Directive = 'FFB0B4D9' }
    }

    # These markup classifications intentionally follow the semantic type lane.
    # Nullsector is excluded because its hot-pink markup lane is an intentional,
    # independently validated part of that theme's cyberpunk hierarchy.
    CoreSyntaxTypeCoupledMarkupThemes = @(
        'Amberroot'
        'Aquatoxic'
        'Biolume'
        'Cosmora'
        'Cosmora Blueshift'
        'Cosmora Redshift'
        'Cosmora Ultraviolet'
        'Foundation'
        'Hardline'
        'Nightglass'
        'Pinknoise'
        'Silverphase'
    )
    CoreSyntaxTypeCoupledMarkupRoles = @(
        @{ Category = 'Text Editor MEF Items'; Role = 'Markup Node' }
        @{ Category = 'Text Editor MEF Items'; Role = 'HTML Element Name' }
    )

    CoreSyntaxDistanceMinimum = 0.06
    CoreSyntaxDistanceAdvisory = 0.08
    CoreSyntaxExactAliasAllowlist = @(
        @{ First = 'Plain'; Second = 'Operator'; Reason = 'Neutral operator/punctuation may intentionally share the plain-text lane.' }
    )

    # These are representative enabled editor-content families whose explicit
    # opaque foregrounds must remain readable when Visual Studio preserves
    # syntax coloring inside an inactive selection.
    EditorSyntaxFamilies = @(
        @{ Category = 'Text Editor Text Manager Items'; Role = 'Plain Text'; Classification = 'plain text' }
        @{ Category = 'Text Editor Language Service Items'; Role = 'Keyword'; Classification = 'keyword' }
        @{ Category = 'Text Editor Language Service Items'; Role = 'String'; Classification = 'string' }
        @{ Category = 'Text Editor Language Service Items'; Role = 'Number'; Classification = 'number' }
        @{ Category = 'Text Editor Language Service Items'; Role = 'Comment'; Classification = 'comment' }
        @{ Category = 'Text Editor MEF Items'; Role = 'method name'; Classification = 'method' }
        @{ Category = 'Text Editor MEF Items'; Role = 'class name'; Classification = 'type' }
        @{ Category = 'Text Editor MEF Items'; Role = 'local name'; Classification = 'local variable' }
        @{ Category = 'Text Editor MEF Items'; Role = 'parameter name'; Classification = 'parameter' }
        @{ Category = 'Text Editor MEF Items'; Role = 'CSS Keyword'; Classification = 'CSS keyword' }
        @{ Category = 'Text Editor MEF Items'; Role = 'CSS Comment'; Classification = 'CSS comment' }
        @{ Category = 'Text Editor MEF Items'; Role = 'CSS Selector'; Classification = 'CSS selector' }
        @{ Category = 'Text Editor MEF Items'; Role = 'CSS Property Name'; Classification = 'CSS property' }
        @{ Category = 'Text Editor MEF Items'; Role = 'CSS Property Value'; Classification = 'CSS value' }
        @{ Category = 'Text Editor MEF Items'; Role = 'CSS String Value'; Classification = 'CSS string' }
        @{ Category = 'Text Editor MEF Items'; Role = 'HTML Element Name'; Classification = 'HTML element' }
        @{ Category = 'Text Editor MEF Items'; Role = 'HTML Attribute Name'; Classification = 'HTML attribute' }
        @{ Category = 'Text Editor MEF Items'; Role = 'HTML Attribute Value'; Classification = 'HTML value' }
        @{ Category = 'Text Editor MEF Items'; Role = 'HTML Entity'; Classification = 'HTML entity' }
        @{ Category = 'Text Editor MEF Items'; Role = 'RazorComponentElement'; Classification = 'Razor component' }
        @{ Category = 'Text Editor MEF Items'; Role = 'RazorDirective'; Classification = 'Razor directive' }
    )

    ScrollbarStateAnchors = @{
        Amberroot = @{ Track = 'FF36382D'; Rest = 'FF838070'; Hover = 'FF8F8C7A'; Pressed = 'FFA49F8D'; Glyph = 'FFF2ECD8'; ArrowRest = 'FFF2ECD8'; ArrowHover = 'FFF2ECD8'; ArrowPressed = 'FFF2ECD8' }
        Aquatoxic = @{ Track = 'FF072E32'; Rest = 'FF5A777B'; Hover = 'FF668286'; Pressed = 'FF799499'; Glyph = 'FFF4FBFD'; ArrowRest = 'FFF4FBFD'; ArrowHover = 'FFF4FBFD'; ArrowPressed = 'FFF4FBFD' }
        Biolume = @{ Track = 'FF111512'; Rest = 'FF5B645E'; Hover = 'FF656F68'; Pressed = 'FF768079'; Glyph = 'FFEDF5EF'; ArrowRest = 'FFEDF5EF'; ArrowHover = 'FFEDF5EF'; ArrowPressed = 'FFEDF5EF' }
        Cosmora = @{ Track = 'FF141825'; Rest = 'FF626475'; Hover = 'FF6C6E7F'; Pressed = 'FF7F7F92'; Glyph = 'FFF1F0F7'; ArrowRest = 'FFF1F0F7'; ArrowHover = 'FFF1F0F7'; ArrowPressed = 'FFF1F0F7' }
        'Cosmora Blueshift' = @{ Track = 'FF0E192B'; Rest = 'FF59667C'; Hover = 'FF637086'; Pressed = 'FF758299'; Glyph = 'FFEDF4FF'; ArrowRest = 'FFEDF4FF'; ArrowHover = 'FFEDF4FF'; ArrowPressed = 'FFEDF4FF' }
        'Cosmora Redshift' = @{ Track = 'FF261510'; Rest = 'FF7A6053'; Hover = 'FF856A5C'; Pressed = 'FF987C6C'; Glyph = 'FFFFF2E9'; ArrowRest = 'FFFFF2E9'; ArrowHover = 'FFFFF2E9'; ArrowPressed = 'FFFFF2E9' }
        'Cosmora Ultraviolet' = @{ Track = 'FF211522'; Rest = 'FF755E6F'; Hover = 'FF81687A'; Pressed = 'FF947A8D'; Glyph = 'FFFFF0F8'; ArrowRest = 'FFFFF0F8'; ArrowHover = 'FFFFF0F8'; ArrowPressed = 'FFFFF0F8' }
        Foundation = @{ Track = 'FF151518'; Rest = 'FF636365'; Hover = 'FF6C6D6E'; Pressed = 'FF7F7F80'; Glyph = 'FFE7E7E7'; ArrowRest = 'FFE7E7E7'; ArrowHover = 'FFE7E7E7'; ArrowPressed = 'FFE7E7E7' }
        Hardline = @{ Track = 'FF151718'; Rest = 'FF616463'; Hover = 'FF6B6F6E'; Pressed = 'FF7D807F'; Glyph = 'FFFAFAF7'; ArrowRest = 'FFFAFAF7'; ArrowHover = 'FFFAFAF7'; ArrowPressed = 'FFFAFAF7' }
        Nightglass = @{ Track = 'FF111827'; Rest = 'FF596577'; Hover = 'FF647082'; Pressed = 'FF758195'; Glyph = 'FFE7E7E7'; ArrowRest = 'FFE7E7E7'; ArrowHover = 'FFE7E7E7'; ArrowPressed = 'FFE7E7E7' }
        Nullsector = @{ Track = 'FF0D121A'; Rest = 'FF58626E'; Hover = 'FF626C79'; Pressed = 'FF737D8C'; Glyph = 'FFE7EEF7'; ArrowRest = 'FFE7EEF7'; ArrowHover = 'FFE7EEF7'; ArrowPressed = 'FFE7EEF7' }
        Pinknoise = @{ Track = 'FF171019'; Rest = 'FF695E68'; Hover = 'FF746872'; Pressed = 'FF867983'; Glyph = 'FFF8EDF3'; ArrowRest = 'FFF8EDF3'; ArrowHover = 'FFF8EDF3'; ArrowPressed = 'FFF8EDF3' }
        Silverphase = @{ Track = 'FF141A24'; Rest = 'FF5C6675'; Hover = 'FF667180'; Pressed = 'FF778394'; Glyph = 'FFE7EEF8'; ArrowRest = 'FFE7EEF8'; ArrowHover = 'FFE7EEF8'; ArrowPressed = 'FFE7EEF8' }
    }

    MarkerHighlightRoles = @{
        Definition = @(
            'MarkerFormatDefinition/CppHighlightedDefinition'
            'MarkerFormatDefinition/HighlightedDefinition'
        )
        Reference = @(
            'MarkerFormatDefinition/HighlightedReference'
            'MarkerFormatDefinition/HighlightedWrittenReference'
        )
        Matched = @(
            'Matched Selected Text'
        )
        Scope = @(
            'MarkerFormatDefinition/ScopeHighlight'
        )
        Expression = @(
            'Expression Hover Highlight'
        )
    }

    FindHighlightAnchors = @{
        Amberroot = 'FF402615'
        Aquatoxic = 'FF233222'
        Biolume = 'FF281D08'
        Cosmora = 'FF221E18'
        'Cosmora Blueshift' = 'FF21231D'
        'Cosmora Redshift' = 'FF311F0B'
        'Cosmora Ultraviolet' = 'FF2D1F17'
        Foundation = 'FF2B1D0F'
        Hardline = 'FF262211'
        Nightglass = 'FF2B1A1B'
        Nullsector = 'FF190929'
        Pinknoise = 'FF2B080D'
        Silverphase = 'FF271413'
    }

    MarkerHighlightAnchors = @{
        Amberroot = @{ ReferenceFill = 'FF312D1F'; ReferenceBorder = 'FFAFC58F'; DefinitionFill = 'FF232921'; DefinitionBorder = 'FF79B985'; MatchedFill = 'FF32332C'; ScopeFill = 'FF2E2B1E'; ExpressionFill = 'FF2A291D'; ExpressionBorder = 'FFE4B84E'; FindBorder = 'FFE4B84E' }
        Aquatoxic = @{ ReferenceFill = 'FF0F3023'; ReferenceBorder = 'FF86E6EC'; DefinitionFill = 'FF0D2A28'; DefinitionBorder = 'FFB3D88C'; MatchedFill = 'FF1F3A3E'; ScopeFill = 'FF0D2D23'; ExpressionFill = 'FF102721'; ExpressionBorder = 'FFE7A830'; FindBorder = 'FFE7A830' }
        Biolume = @{ ReferenceFill = 'FF0C211D'; ReferenceBorder = 'FFC4B5FD'; DefinitionFill = 'FF131A0C'; DefinitionBorder = 'FFA3E635'; MatchedFill = 'FF212623'; ScopeFill = 'FF0B1E1A'; ExpressionFill = 'FF191A0D'; ExpressionBorder = 'FFFDE047'; FindBorder = 'FFFDE047' }
        Cosmora = @{ ReferenceFill = 'FF13162E'; ReferenceBorder = 'FFBEB8EE'; DefinitionFill = 'FF0C1A20'; DefinitionBorder = 'FF34D399'; MatchedFill = 'FF242633'; ScopeFill = 'FF12152A'; ExpressionFill = 'FF1A1918'; ExpressionBorder = 'FFFBBF24'; FindBorder = 'FFFBBF24' }
        'Cosmora Blueshift' = @{ ReferenceFill = 'FF101B32'; ReferenceBorder = 'FFAEC5F5'; DefinitionFill = 'FF0C1A20'; DefinitionBorder = 'FF34D399'; MatchedFill = 'FF222B39'; ScopeFill = 'FF0E1A2F'; ExpressionFill = 'FF1A1918'; ExpressionBorder = 'FFFBBF24'; FindBorder = 'FFFBBF24' }
        'Cosmora Redshift' = @{ ReferenceFill = 'FF2E140C'; ReferenceBorder = 'FFF3B69B'; DefinitionFill = 'FF0C1A20'; DefinitionBorder = 'FF34D399'; MatchedFill = 'FF372620'; ScopeFill = 'FF2B130B'; ExpressionFill = 'FF1A1918'; ExpressionBorder = 'FFFBBF24'; FindBorder = 'FFFBBF24' }
        'Cosmora Ultraviolet' = @{ ReferenceFill = 'FF24152C'; ReferenceBorder = 'FFD5B7F1'; DefinitionFill = 'FF0C1A20'; DefinitionBorder = 'FF34D399'; MatchedFill = 'FF332632'; ScopeFill = 'FF221329'; ExpressionFill = 'FF1A1918'; ExpressionBorder = 'FFFBBF24'; FindBorder = 'FFFBBF24' }
        Foundation = @{ ReferenceFill = 'FF171F2B'; ReferenceBorder = 'FF5EEAD4'; DefinitionFill = 'FF121D19'; DefinitionBorder = 'FF4ADE80'; MatchedFill = 'FF28282B'; ScopeFill = 'FF161C27'; ExpressionFill = 'FF1F1B11'; ExpressionBorder = 'FFFACC15'; FindBorder = 'FFFACC15' }
        Hardline = @{ ReferenceFill = 'FF231B0D'; ReferenceBorder = 'FF89AABD'; DefinitionFill = 'FF101711'; DefinitionBorder = 'FF7FCB75'; MatchedFill = 'FF222424'; ScopeFill = 'FF1F180C'; ExpressionFill = 'FF19170E'; ExpressionBorder = 'FFFFD34D'; FindBorder = 'FFFFD34D' }
        Nightglass = @{ ReferenceFill = 'FF0F2033'; ReferenceBorder = 'FFA5B4FC'; DefinitionFill = 'FF0E1E29'; DefinitionBorder = 'FF34D399'; MatchedFill = 'FF232A3B'; ScopeFill = 'FF0F2034'; ExpressionFill = 'FF1C1D1F'; ExpressionBorder = 'FFFACC15'; FindBorder = 'FFFACC15' }
        Nullsector = @{ ReferenceFill = 'FF071510'; ReferenceBorder = 'FF2ED9FF'; DefinitionFill = 'FF0C1416'; DefinitionBorder = 'FF67E480'; MatchedFill = 'FF13171F'; ScopeFill = 'FF071410'; ExpressionFill = 'FF121111'; ExpressionBorder = 'FFFFB000'; FindBorder = 'FFFFB000' }
        Pinknoise = @{ ReferenceFill = 'FF1F131C'; ReferenceBorder = 'FF56D8D0'; DefinitionFill = 'FF10181A'; DefinitionBorder = 'FF34D399'; MatchedFill = 'FF241F25'; ScopeFill = 'FF23151F'; ExpressionFill = 'FF1C1610'; ExpressionBorder = 'FFFACC15'; FindBorder = 'FFFACC15' }
        Silverphase = @{ ReferenceFill = 'FF101B26'; ReferenceBorder = 'FF7EE6F2'; DefinitionFill = 'FF0E1B1E'; DefinitionBorder = 'FF34D399'; MatchedFill = 'FF1C2129'; ScopeFill = 'FF111D2A'; ExpressionFill = 'FF161816'; ExpressionBorder = 'FFFACC15'; FindBorder = 'FFFACC15' }
    }

    CurrentLineAnchors = @{
        Biolume = 'FF141915'
        Cosmora = 'FF161A27'
        'Cosmora Blueshift' = 'FF121D2F'
        'Cosmora Redshift' = 'FF2A1813'
        'Cosmora Ultraviolet' = 'FF251825'
        Foundation = 'FF1C1C1F'
        Nightglass = 'FF171F2E'
        Nullsector = 'FF131921'
        Pinknoise = 'FF1D161F'
        Silverphase = 'FF161D27'
    }

    ActiveSelectionAnchors = @{
        'Foundation' = 'FF566273'
        'Pinknoise' = 'FF555E60'
        'Cosmora' = 'FF616074'
        'Cosmora Blueshift' = 'FF576276'
        'Cosmora Redshift' = 'FF775C57'
        'Cosmora Ultraviolet' = 'FF6C5A6C'
        'Nullsector' = 'FF475861'
        'Aquatoxic' = 'FF4F7476'
        'Hardline' = 'FF657682'
        'Biolume' = 'FF4C6964'
        'Nightglass' = 'FF506475'
        'Silverphase' = 'FF555D79'
        'Amberroot' = 'FF687564'
    }

    InactiveSelectionAnchors = @{
        'Amberroot' = 'FF5A5440'
        'Aquatoxic' = 'FF385837'
        'Biolume' = 'FF324E49'
        Cosmora = 'FF474565'
        'Cosmora Blueshift' = 'FF3A4665'
        'Cosmora Redshift' = 'FF634034'
        'Cosmora Ultraviolet' = 'FF513D5F'
        Foundation = 'FF3D4958'
        'Hardline' = 'FF4E5659'
        'Nullsector' = 'FF334149'
        'Nightglass' = 'FF37495B'
        Pinknoise = 'FF4E3E49'
        'Silverphase' = 'FF374551'
    }

    ContextualEditorOverlays = @(
        @{ Theme = 'Amberroot'; Role = 'CodeAnalysisCurrentStatementSelection'; Background = '50D8AB52'; Minimum = 4.5 }
        @{ Theme = 'Amberroot'; Role = 'CodeAnalysisKeyEventSelection'; Background = '50D8AB52'; Minimum = 4.5 }
        @{ Theme = 'Amberroot'; Role = 'CodeAnalysisLineTraceSelection'; Background = '50D8AB52'; Minimum = 4.5 }
        @{ Theme = 'Amberroot'; Role = 'Current Statement'; Background = 'FF453D26'; Minimum = 4.5 }
        @{ Theme = 'Amberroot'; Role = 'Current Statement (new context)'; Background = 'FF453D26'; Minimum = 4.5 }
        @{ Theme = 'Amberroot'; Role = 'Current Statement (historical mode)'; Background = 'FF453D26'; Minimum = 4.5 }
    )

    HardlineNeutralSeparators = @(
        'ClassDesignerCompartmentSeparator'
        'CommandBarMenuMouseOverSeparator'
        'CommandBarMenuSeparator'
        'CommandBarSplitButtonSeparator'
        'CommandBarToolBarSeparator'
        'FileTabPrimarySeparator'
        'FileTabSecondarySeparator'
        'PageContentExpanderSeparator'
        'PageSideBarExpanderSeparator'
        'PanelSeparator'
        'PanelSubGroupSeparator'
        'StartPageSeparator'
        'ToolboxDivider'
        'ToolWindowTabSeparator'
    )

    HardlineStrongNeutralBorders = @(
        'ComboBoxBorder'
        'ControlOutline'
        'ScrollBarBorder'
        'ToolWindowBorder'
    )

    SeparatorAdvisories = @(
        @{
            Role = 'PanelSeparator'
            SurfaceCategory = 'Shell'
            SurfaceRole = 'SolidBackgroundFillBase'
            ReferenceRatio = 1.52
            Reason = 'Extension Manager and other shared consumers require runtime confirmation at high DPI and increased text scaling.'
        }
    )

    # Bounded September 2026 refinement requirements; values are project choices.
    EditorSelectionModel = 'normal-selection-18.10'
    PrioritySelectionMinimum = 4.5
    PrioritySelectionDistanceMinimum = 0.03
    # Source-check scope is independent of package ownership. Pending themes
    # retain their established checks; migration enables this expanded suite.
    RefinementEnforcement = @{
        'Amberroot' = 'enforced'
        'Aquatoxic' = 'enforced'
        'Biolume' = 'enforced'
        Cosmora = 'enforced'
        'Cosmora Blueshift' = 'enforced'
        'Cosmora Redshift' = 'enforced'
        'Cosmora Ultraviolet' = 'enforced'
        Foundation = 'enforced'
        'Hardline' = 'enforced'
        'Nightglass' = 'enforced'
        'Nullsector' = 'enforced'
        Pinknoise = 'enforced'
        'Silverphase' = 'enforced'
    }
    PriorityRefinementAnchors = @{
        'Foundation' = @{ ControlSolidFillDefault = 'FF424248'; EditorActiveSelectionFill = 'FF566273'; EditorInactiveSelectionFill = 'FF3D4958'; LegacyDisabledBorder = 'FF424248' }
        'Pinknoise' = @{ ControlSolidFillDefault = 'FF4A2D3E'; EditorActiveSelectionFill = 'FF555E60'; LineNumber = 'FFC9A9B8'; SelectedLineNumber = 'FFE58CC7'; InactivePaneBorder = 'FF49303F'; EditorInactiveSelectionFill = 'FF4E3E49' }
        'Cosmora' = @{ ControlSolidFillDefault = 'FF36394B'; EditorActiveSelectionFill = 'FF616074'; ToolbarLayeredBorder = '804A4D64'; EditorInactiveSelectionFill = 'FF474565' }
        'Cosmora Blueshift' = @{ ControlSolidFillDefault = 'FF293A4D'; EditorActiveSelectionFill = 'FF576276'; ToolbarLayeredBorder = '88425A78'; EditorInactiveSelectionFill = 'FF3A4665' }
        'Cosmora Redshift' = @{ ControlSolidFillDefault = 'FF4D352F'; EditorActiveSelectionFill = 'FF775C57'; ToolbarLayeredBorder = '88724F46'; EditorInactiveSelectionFill = 'FF634034' }
        'Cosmora Ultraviolet' = @{ ControlSolidFillDefault = 'FF47384B'; EditorActiveSelectionFill = 'FF6C5A6C'; ToolbarLayeredBorder = '8866506A'; EditorInactiveSelectionFill = 'FF513D5F' }
        'Aquatoxic' = @{ ControlSolidFillDefault = 'FF2D4F4E'; EditorActiveSelectionFill = 'FF4F7476'; EditorInactiveSelectionFill = 'FF385837' }
        'Hardline' = @{ ControlSolidFillDefault = 'FF34393C'; EditorActiveSelectionFill = 'FF657682'; EditorInactiveSelectionFill = 'FF4E5659' }
        'Biolume' = @{ ControlSolidFillDefault = 'FF3A463F'; EditorActiveSelectionFill = 'FF4C6964'; EditorInactiveSelectionFill = 'FF324E49' }
        'Nightglass' = @{ ControlSolidFillDefault = 'FF313B50'; EditorActiveSelectionFill = 'FF506475'; EditorInactiveSelectionFill = 'FF37495B' }
        'Silverphase' = @{ ControlSolidFillDefault = 'FF323E53'; EditorActiveSelectionFill = 'FF555D79'; EditorInactiveSelectionFill = 'FF374551' }
        'Nullsector' = @{ ControlSolidFillDefault = 'FF101722'; EditorActiveSelectionFill = 'FF475861'; EditorInactiveSelectionFill = 'FF334149' }
        'Amberroot' = @{ ControlSolidFillDefault = 'FF414438'; EditorActiveSelectionFill = 'FF687564'; EditorInactiveSelectionFill = 'FF5A5440' }
    }
}
