#import "PanelController.h"
#import "BackgroundView.h"
#import "StatusItemView.h"
#import "MenubarController.h"

#define OPEN_DURATION .15
#define CLOSE_DURATION .1

#define POPUP_HEIGHT 350
#define MENU_ANIMATION_DURATION .1

#pragma mark -

@implementation PanelController

@synthesize backgroundView = _backgroundView;
@synthesize delegate = _delegate;

#pragma mark -

- (id)initWithDelegate:(id<PanelControllerDelegate>)delegate
{
    self = [super initWithWindowNibName:@"StatusBarPopup"];
    if (self != nil)
    {
        _delegate = delegate;
        reminders = [Reminders new];
        loginStartupDelegate = [LoginStartupDelegate new];
    }
    return self;
}

- (void)dealloc
{
}

#pragma mark -

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    // Make a fully skinned panel
    NSPanel *panel = (id)[self window];
    [panel setAcceptsMouseMovedEvents:YES];
    [panel setLevel:NSPopUpMenuWindowLevel];
    [panel setOpaque:NO];
    [panel setBackgroundColor:[NSColor clearColor]];
    
    // Resize panel
    //NSRect panelRect = [[self window] frame];
    //panelRect.size.height = POPUP_HEIGHT;
    //[[self window] setFrame:panelRect display:NO];
    
    // Tab selection
    [tabView setDelegate: self];
    NSTabViewItem *firstTabView = [self->tabView tabViewItemAtIndex:0];
    NSTabViewItem *secondTabView = [self->tabView tabViewItemAtIndex:1];
    [secondTabView setView: [firstTabView view]];
    
    [startStopButton setAction:@selector(startStopReminderInActiveTab)];
    [quitButton setAction:@selector(quitApplication)];
}

#pragma mark - Public accessors

- (BOOL)hasActivePanel
{
    return _hasActivePanel;
}

- (void)setHasActivePanel:(BOOL)flag
{
    if (_hasActivePanel != flag)
    {
        _hasActivePanel = flag;
        
        if (_hasActivePanel)
        {
            [self openPanel];
        }
        else
        {
            [self closePanel];
        }
    }
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification
{
    self.hasActivePanel = NO;
}

- (void)windowDidResignKey:(NSNotification *)notification;
{
    if ([[self window] isVisible])
    {
        self.hasActivePanel = NO;
    }
}

- (void)windowDidResize:(NSNotification *)notification
{
    NSWindow *panel = [self window];
    NSRect statusRect = [self statusRectForWindow:panel];
    NSRect panelRect = [panel frame];
    
    CGFloat statusX = roundf(NSMidX(statusRect));
    CGFloat panelX = statusX - NSMinX(panelRect);
    
    self.backgroundView.arrowX = panelX;
    
}

#pragma mark - NSTabView

- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    [self saveReminder];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    [self displaySelectedTab];
}

#pragma mark - Keyboard

- (void)cancelOperation:(id)sender
{
    self.hasActivePanel = NO;
}

#pragma mark - Public methods

- (NSRect)statusRectForWindow:(NSWindow *)window
{
    NSRect screenRect = [[[NSScreen screens] objectAtIndex:0] frame];
    NSRect statusRect = NSZeroRect;
    
    StatusItemView *statusItemView = nil;
    if ([self.delegate respondsToSelector:@selector(statusItemViewForPanelController:)])
    {
        statusItemView = [self.delegate statusItemViewForPanelController:self];
    }
    
    if (statusItemView)
    {
        statusRect = statusItemView.globalRect;
        statusRect.origin.y = NSMinY(statusRect) - NSHeight(statusRect);
    }
    else
    {
        statusRect.size = NSMakeSize(STATUS_ITEM_VIEW_WIDTH, [[NSStatusBar systemStatusBar] thickness]);
        statusRect.origin.x = roundf((NSWidth(screenRect) - NSWidth(statusRect)) / 2);
        statusRect.origin.y = NSHeight(screenRect) - NSHeight(statusRect) * 2;
    }
    return statusRect;
}

- (void)openPanel
{
    NSWindow *panel = [self window];
    
    NSRect screenRect = [[[NSScreen screens] objectAtIndex:0] frame];
    NSRect statusRect = [self statusRectForWindow:panel];

    NSRect panelRect = [panel frame];
    panelRect.origin.x = roundf(NSMidX(statusRect) - NSWidth(panelRect) / 2);
    panelRect.origin.y = NSMaxY(statusRect) - NSHeight(panelRect);
    
    if (NSMaxX(panelRect) > (NSMaxX(screenRect) - ARROW_HEIGHT))
        panelRect.origin.x -= NSMaxX(panelRect) - (NSMaxX(screenRect) - ARROW_HEIGHT);
    
    [NSApp activateIgnoringOtherApps:NO];
    [panel setAlphaValue:0];
    [panel setFrame:statusRect display:YES];
    [panel makeKeyAndOrderFront:nil];
    
    NSTimeInterval openDuration = OPEN_DURATION;
    
    NSEvent *currentEvent = [NSApp currentEvent];
    if ([currentEvent type] == NSLeftMouseDown)
    {
        NSUInteger clearFlags = ([currentEvent modifierFlags] & NSDeviceIndependentModifierFlagsMask);
        BOOL shiftPressed = (clearFlags == NSShiftKeyMask);
        BOOL shiftOptionPressed = (clearFlags == (NSShiftKeyMask | NSAlternateKeyMask));
        if (shiftPressed || shiftOptionPressed)
        {
            openDuration *= 10;
            
            if (shiftOptionPressed)
                NSLog(@"Icon is at %@\n\tMenu is on screen %@\n\tWill be animated to %@",
                      NSStringFromRect(statusRect), NSStringFromRect(screenRect), NSStringFromRect(panelRect));
        }
    }
    
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:openDuration];
    [[panel animator] setFrame:panelRect display:YES];
    [[panel animator] setAlphaValue:1];
    [NSAnimationContext endGrouping];
    
    [self displaySelectedTab];
    
    NSLog(@"opening panel");
}

- (void)closePanel
{
    [self saveReminder];
    
    NSLog(@"closing panel");
    
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:CLOSE_DURATION];
    [[[self window] animator] setAlphaValue:0];
    [NSAnimationContext endGrouping];
    
    dispatch_after(dispatch_walltime(NULL, NSEC_PER_SEC * CLOSE_DURATION * 2), dispatch_get_main_queue(), ^{
        
        [self.window orderOut:nil];
    });
}

- (void) displaySelectedTab
{
    NSString *tabViewItemId = [[tabView selectedTabViewItem] identifier];
    
    NSLog(@"tabViewItemId  %@ ", tabViewItemId);
    
    if ([tabViewItemId isEqualToString: @"preferences_tab"])
    {
        if ([loginStartupDelegate isEnabled]){
            [loginStartupPreferenceButton setState: NSOnState];
        } else {
            [loginStartupPreferenceButton setState: NSOffState];
        }
        
        [loginStartupPreferenceButton setAction:@selector(handleLoginStartupPreference)];
    } else {
        
        [self initFormFields: tabViewItemId];
        // Default cursor to reminder text field
        [reminderTextField selectText:self];
        [[reminderTextField currentEditor] setSelectedRange:NSMakeRange([[reminderTextField stringValue] length], 0)];
    }
    
    for (Reminder *reminder in [reminders getAllReminders]){
        if ([reminder isRunning]){
            [self displayReminderIsRunning:[reminder reminderId]];
        } else {
            [self displayReminderNotRunning:[reminder reminderId]];
        }
    }
}

- (NSString *)getReminderTextByPreferenceReminderId:(NSString *)preferenceReminderId preferences:(NSUserDefaults *)preferences
{
    NSString *reminderText = [preferences stringForKey:[@"reminderText" stringByAppendingString:preferenceReminderId]];
    if ([reminderText length] == 0){
        if ([[self getReminderIdOfCurrentTab] isEqualToString: @"1"]){
            reminderText = @"Get up. Take a Deep Breath. Stretch your legs.";
        } else {
            reminderText = @"Another reminder...";
        }
    }
    return reminderText;
}

- (void)initFormFields: (NSString*) reminderId
{
    NSString *preferenceReminderId = [self getPreferenceReminderId:reminderId];

    NSUserDefaults *prefs = [self loadPreferences];
    NSString *reminderText = [self getReminderTextByPreferenceReminderId:preferenceReminderId preferences:prefs];
    [reminderTextField setStringValue:reminderText];
    
    NSInteger reminderPeriodInMinutes = [prefs integerForKey:[@"reminderPeriod" stringByAppendingString:preferenceReminderId]];
    if (reminderPeriodInMinutes == 0){
        if ([reminderId isEqualToString:@"1"]){
            reminderPeriodInMinutes = 30;
        } else {
            reminderPeriodInMinutes = 60;
        }
    }
    [self setReminderPeriod:reminderPeriodInMinutes];
}

- (NSUserDefaults *)loadPreferences
{
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    return prefs;
}

- (NSString *)getReminderIdOfCurrentTab
{
    return [[tabView selectedTabViewItem] identifier];
}

- (void) saveReminder
{
    NSString* tabViewItemId = [self getReminderIdOfCurrentTab];    
    NSLog(@"tabViewItemId  %@ ", tabViewItemId);
    
    if ([tabViewItemId isEqualToString: @"preferences_tab"]){
        return;
    }
    
    NSString *internalReminderId = [self getPreferenceReminderId:tabViewItemId];    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:[reminderTextField stringValue] forKey:[@"reminderText" stringByAppendingString:internalReminderId]];
    [prefs setInteger:[self getReminderPeriod] forKey:[@"reminderPeriod" stringByAppendingString:internalReminderId]];
    [prefs synchronize];
}

// For backwards compatibility until I figure out how to migrate data on application re-install
- (NSString *)getPreferenceReminderId:(NSString*)reminderId
{
    NSString* internalReminderId = @"";
    if ([reminderId isEqualToString: @"2"]){
        internalReminderId = @"_two";
    }
    return internalReminderId;
}

- (void)displayReminderIsRunning:(NSString*)reminderId
{
    [[self getStatusLabelByReminderId:reminderId] setHidden:FALSE];
    [[[[self getStatusLabelByReminderId:reminderId] superview] superview] setHidden:FALSE];
    
    if ([reminderId isEqualToString:[self getReminderIdOfCurrentTab]]){
        [startStopButton setTitle:@"Turn Off"];
        [reminderMinutePeriodField setEnabled:FALSE];
        [reminderHourPeriodField setEnabled:FALSE];
    }
}

- (void)displayReminderNotRunning:(NSString*)reminderId
{
    [[self getStatusLabelByReminderId:reminderId] setStringValue: @""];
    [[[[self getStatusLabelByReminderId:reminderId] superview] superview] setHidden:TRUE];

    if ([reminderId isEqualToString:[self getReminderIdOfCurrentTab]]){
        [startStopButton setTitle:@"Turn On"];
        [reminderMinutePeriodField setEnabled:TRUE];
        [reminderHourPeriodField setEnabled:TRUE];
    }
}

- (NSTextField*) getStatusLabelByReminderId:(NSString*)reminderId
{
    if ([reminderId isEqualToString: @"1"]){
        return statusLabelOne;
    }
    
    return statusLabelTwo;
}

- (void) startStopReminderInActiveTab {
    if ([[startStopButton title] isEqualToString:@"Turn On"]){
        [self saveReminder];
        [self startReminderTimer];
        [self displayReminderIsRunning:[self getReminderIdOfCurrentTab]];
    } else {
        [self stopReminderTimer];
        [self displayReminderNotRunning:[self getReminderIdOfCurrentTab]];
    }
}

- (void) startReminderTimer {
    
    NSString *tabViewItemId = [[tabView selectedTabViewItem] identifier];
    NSLog(@"tabViewItemId  %@ ", tabViewItemId);
    
    Reminder* reminder = [reminders getReminderById:tabViewItemId];
    [reminder setReminderPeriod: [self getReminderPeriod]];
    
    [reminder setOnReminderPeriodUpdated:^(Reminder *reminderArg){        
        [self displayNextReminderMessage:reminderArg];
    }];

    [reminder setOnReminderPeriodFinished:^(Reminder *reminderArg){
        [self displayFinishReminderMessage:reminderArg];
    }];
    
    [reminder start];
    
    [self displayNextReminderMessage:reminder];
    NSLog(@"Started Timer...");
}

- (void) stopReminderTimer {
    
    NSString *tabViewItemId = [[tabView selectedTabViewItem] identifier];
    NSLog(@"tabViewItemId  %@ ", tabViewItemId);
    [[reminders getReminderById:tabViewItemId] stop];    
}

- (BOOL) userNotificationCenter:(NSUserNotificationCenter *)center
     shouldPresentNotification:(NSUserNotification *)notification{
    return YES;
}

- (NSInteger) getReminderPeriod {
    NSInteger minutes = [reminderMinutePeriodField integerValue];
    NSInteger hours = [reminderHourPeriodField integerValue];
    minutes = hours * 60 + minutes;
    NSLog(@"Reminder is set to %ld minutes", minutes);
    return minutes;
}

- (void)setReminderPeriod:(NSInteger)reminderPeriodInMinutes {
    NSLog(@"Reminder in minutes is %ld", reminderPeriodInMinutes);
    NSInteger hours = reminderPeriodInMinutes / 60;
    NSInteger minutes = reminderPeriodInMinutes % 60;
    [reminderHourPeriodField setIntegerValue:hours];
    [reminderMinutePeriodField setIntegerValue:minutes];
}

- (void) displayNextReminderMessage:(Reminder *)reminder {
    NSInteger hours = [reminder minutesRemainingForNextReminder] / 60;
    NSInteger minutes = [reminder minutesRemainingForNextReminder] % 60;
    
    [[self getStatusLabelByReminderId:[reminder reminderId]]
                                setStringValue:[NSString stringWithFormat:@"%02ld:%02ld", hours, minutes]];
}

- (void) displayFinishReminderMessage:(Reminder *)reminder {
    // save first so that the notification has the latest reminder text
    [self saveReminder];
    
    NSString* reminderText = [self getReminderTextByPreferenceReminderId:[self getPreferenceReminderId:[reminder reminderId]] preferences:[self loadPreferences]];
    
    NSUserNotification *notification = [[NSUserNotification alloc] init];
    notification.title = @"Remind Me Again";
    notification.informativeText = reminderText;
    notification.soundName = NSUserNotificationDefaultSoundName;
    notification.hasActionButton = FALSE;
    [notification setOtherButtonTitle: @"Close"];
    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}

- (void) handleLoginStartupPreference
{
    
    if ([loginStartupPreferenceButton state] == NSOnState){
        [loginStartupDelegate enable];
    } else {
        [loginStartupDelegate disable];
    }
}

- (void) quitApplication {
    [NSApp terminate:self];
}

@end
