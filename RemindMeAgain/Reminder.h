//
//  Reminder.h
//  RemindMeAgain
//
//  Created by Kavan Puranik on 6/25/13.
//  Copyright (c) 2013 Kavan Puranik. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Reminder : NSObject

@property NSString *description;
@property (weak) NSTimer *repeatingTimer;
@property NSInteger minutesRemainingForNextReminder;
@property NSInteger reminderPeriod;

- (id) initWithReminderId: (NSString*) reminderId;

#pragma mark - Callbacks
@property (copy) void (^onReminderPeriodDecremented)(Reminder *reminder);
@property (copy) void (^onReminderPeriodFinished)(Reminder *reminder);

- (void) start;

- (void) stop;

- (BOOL) isRunning;

@end