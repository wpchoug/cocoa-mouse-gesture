//
//  AppDelegate.m
//  MouseGesture
//
//  Created by keakon on 11-11-9.
//  Copyright (c) 2011年 keakon.net. All rights reserved.
//
#include <Carbon/Carbon.h>
#import "AppDelegate.h"
#import "CanvasWindowController.h"

@implementation AppDelegate

typedef enum {
	NONE,
	RIGHT,
	UP,
	LEFT,
	DOWN,
} DIRECTION;

typedef enum {
	NOT_TABBED_APPLICATION,
	CHROME,
	SAFARI,
	FIREFOX
	// add more if needed
} TABBED_APPLICATION;

typedef struct {
	UniCharCount length;
	UniChar *string;
} UnicodeStruct;

static CanvasWindowController *windowController;
static CGEventRef mouseDownEvent, mouseDraggedEvent;
static const unsigned int MAX_DIRECTIONS = 128;
static DIRECTION directions[MAX_DIRECTIONS];
static unsigned int directionLength;
static NSPoint lastLocation;
static CFMachPortRef mouseEventTap;
static bool isEnable;
static UnicodeStruct username;
static UnicodeStruct password;
static UnicodeStruct email;

static inline pid_t getFrontProcessPID() {
	ProcessSerialNumber psn;
	pid_t pid;
	if (GetFrontProcess(&psn) == noErr && GetProcessPID(&psn, &pid) == noErr) {
		return pid;
	}
	return -1;
}

static inline NSString *getFrontProcessName() {
	ProcessSerialNumber psn;
	CFStringRef nameRef;
	if (GetFrontProcess(&psn) == noErr && CopyProcessName(&psn, &nameRef) == noErr) {
		NSString *name = [[(NSString *)nameRef copy] autorelease];
		CFRelease(nameRef);
		return name;
	}
	return nil;
}

static inline void pressButtonInMainWindowOfProcess(pid_t pid, CFStringRef buttonName) {
	if (AXAPIEnabled()) {
		AXUIElementRef app = AXUIElementCreateApplication(pid);
		AXUIElementRef mainWindow = NULL;
		if (AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute, (CFTypeRef *)&mainWindow) == noErr) {
			AXUIElementRef button = NULL;
			if (AXUIElementCopyAttributeValue(mainWindow, buttonName, (CFTypeRef *)&button) == noErr) {
				AXUIElementPerformAction(button, kAXPressAction);
				CFRelease(button);
			}
			CFRelease(mainWindow);
		}
		CFRelease(app);
	}
}

/*
static NSRunningApplication *getActiveApplication() {
	NSArray *runningApplications = NSWorkspace.sharedWorkspace.runningApplications;
	for (NSRunningApplication *application in runningApplications) {
		if (application.active) {
			return application;
		}
	}
	return nil;
}
*/

static inline TABBED_APPLICATION isWhichTabbedApplication() {
	NSString *name = getFrontProcessName();
	if (name) {
		if ([name hasPrefix:@"Google Chrome"]) {
			return CHROME;
		} else if ([name isEqualToString:@"Safari"]) {
			return SAFARI;
		} else if ([name isEqualToString:@"Firefox"]) {
			return FIREFOX;
		}
	}
	return NOT_TABBED_APPLICATION;
}

static inline void pressKey(CGKeyCode virtualKey) {
	CGEventRef event = CGEventCreateKeyboardEvent(NULL, virtualKey, true);
	CGEventPost(kCGSessionEventTap, event);
	CFRelease(event);
	
	event = CGEventCreateKeyboardEvent(NULL, virtualKey, false);
	CGEventPost(kCGSessionEventTap, event);
	CFRelease(event);
}

static inline void pressKeyWithFlags(CGKeyCode virtualKey, CGEventFlags flags) {
	CGEventRef event = CGEventCreateKeyboardEvent(NULL, virtualKey, true);
	CGEventSetFlags(event, flags);
	CGEventPost(kCGSessionEventTap, event);
	CFRelease(event);
	
	event = CGEventCreateKeyboardEvent(NULL, virtualKey, false);
	CGEventSetFlags(event, flags);
	CGEventPost(kCGSessionEventTap, event);
	CFRelease(event);
}

static inline void copyUnicodeString(NSString *string, UnicodeStruct *unicodeStruct) { // should release unicodeStruct->string
	unicodeStruct->length = string.length;
	unicodeStruct->string = (UniChar *)malloc(sizeof(UniChar) * unicodeStruct->length);
	[string getCharacters:unicodeStruct->string range:NSMakeRange(0, unicodeStruct->length)];
}

static inline void typeSting(UnicodeStruct *unicodeStruct) {
	CGEventRef event = CGEventCreateKeyboardEvent(NULL, 0, true);
	CGEventKeyboardSetUnicodeString(event, unicodeStruct->length, unicodeStruct->string);
	CGEventPost(kCGSessionEventTap, event);
	CFRelease(event);
	
	event = CGEventCreateKeyboardEvent(NULL, 0, false); // not sure whether it's needed
	CGEventKeyboardSetUnicodeString(event, unicodeStruct->length, unicodeStruct->string);
	CGEventPost(kCGSessionEventTap, event);
	CFRelease(event);
}

/*
static inline void typeSting(NSString *string) {
	UniCharCount stringLength = string.length;
	UniChar *unicodeString = (UniChar *)malloc(sizeof(UniChar) * stringLength);
	[string getCharacters:unicodeString range:NSMakeRange(0, stringLength)];

	CGEventRef event = CGEventCreateKeyboardEvent(NULL, 0, true);
	CGEventKeyboardSetUnicodeString(event, stringLength, unicodeString);
	CGEventPost(kCGSessionEventTap, event);
	CFRelease(event);
	
	event = CGEventCreateKeyboardEvent(NULL, 0, false); // not sure whether it's needed
	CGEventKeyboardSetUnicodeString(event, stringLength, unicodeString);
	CGEventPost(kCGSessionEventTap, event);
	CFRelease(event);
	free(unicodeString);
}
*/

static void updateDirections(NSEvent* event) {
	// not thread safe
	NSPoint newLocation = event.locationInWindow;
	float deltaX = newLocation.x - lastLocation.x;
	float deltaY = newLocation.y - lastLocation.y;
	float absX = fabs(deltaX);
	float absY = fabs(deltaY);
	if (absX + absY < 20) {
		return; // ignore short distance
	}
	
	lastLocation = newLocation;
	if (directionLength == MAX_DIRECTIONS) {
		return; // ignore more directions
	}
	DIRECTION lastDirection = directionLength ? directions[directionLength - 1] : NONE;
	if (absX > absY) {
		if (deltaX > 0) {
			if (lastDirection != RIGHT) {
				directions[directionLength++] = RIGHT;
			}
		} else if (lastDirection != LEFT) {
			directions[directionLength++] = LEFT;
		}
	} else {
		if (deltaY > 0) {
			if (lastDirection != UP) {
				directions[directionLength++] = UP;
			}
		} else if (lastDirection != DOWN) {
			directions[directionLength++] = DOWN;
		}
	}
}

static bool handleGesture() {
	// not thread safe
	switch (directionLength) {
		case 1:
			switch (directions[0]) {
				case UP:	// go to top
					pressKey(kVK_Home);
					break;
				case DOWN:	// go to bottom
					pressKey(kVK_End);
					break;
				case LEFT:	// change to left space
					pressKeyWithFlags(kVK_LeftArrow, kCGEventFlagMaskControl);
					break;
				case RIGHT:	// change to right space
					pressKeyWithFlags(kVK_RightArrow, kCGEventFlagMaskControl);
					break;
				default:
					return false;
			}
			return true;
		case 2:
			switch (directions[0]) {
				case UP:
					if (directions[1] == DOWN) { // page up
						pressKey(kVK_PageUp);
						return true;
					} else if (directions[1] == RIGHT) { // switch full screen mode
						// should check process name, some process may not use this hotkey
						pressKeyWithFlags(kVK_ANSI_F, kCGEventFlagMaskControl | kCGEventFlagMaskCommand);
						return true;
						/* don't work in some process and can't exit full screen mode
						pid_t pid = getFrontProcessPID();
						if (pid > 0) {
							pressButtonInMainWindowOfProcess(pid, kAXFullScreenButtonAttribute);
							return true;
						}
						*/
					}
					break;
				case DOWN:
					switch (directions[1]) {
						case UP:	// page down
							pressKey(kVK_PageDown);
							return true;
						case LEFT:	// print user name
							typeSting(&username);
							return true;
						case RIGHT:	// print password
							typeSting(&password);
							return true;
						default:
							break;
					}
					break;
				case LEFT:
					switch (directions[1]) {
						case UP: { // zoom
							pid_t pid = getFrontProcessPID();
							if (pid > 0) {
								pressButtonInMainWindowOfProcess(pid, kAXZoomButtonAttribute);
								return true;
							}
						}
						case DOWN: // minimize
							pressKeyWithFlags(kVK_ANSI_M, kCGEventFlagMaskCommand);
							return true;
						case RIGHT: // change to left tab
							switch (isWhichTabbedApplication()) {
								case CHROME:
									pressKeyWithFlags(kVK_LeftArrow, kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand);
									return true;
								case SAFARI:
									pressKeyWithFlags(kVK_LeftArrow, kCGEventFlagMaskShift | kCGEventFlagMaskCommand);
									return true;
								case FIREFOX:
									pressKeyWithFlags(kVK_Tab, kCGEventFlagMaskShift | kCGEventFlagMaskControl);
									return true;
								default:
									break;
							}
						default:
							break;
					}
					break;
				case RIGHT:
					switch (directions[1]) {
						case DOWN: // close window / tab
							pressKeyWithFlags(kVK_ANSI_W, kCGEventFlagMaskCommand);
							return true;
						case UP: { // reopen last closed tab
							switch (isWhichTabbedApplication()) {
								case CHROME:
								case FIREFOX: // same hotkey
									pressKeyWithFlags(kVK_ANSI_T, kCGEventFlagMaskShift | kCGEventFlagMaskCommand);
									return true;
								case SAFARI:
									pressKeyWithFlags(kVK_ANSI_Z, kCGEventFlagMaskCommand);
									return true;
								default:
									break;
							}
						}
						case LEFT: { // change to right tab
							switch (isWhichTabbedApplication()) {
								case CHROME:
									pressKeyWithFlags(kVK_RightArrow, kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand);
									return true;
								case SAFARI:
									pressKeyWithFlags(kVK_RightArrow, kCGEventFlagMaskShift | kCGEventFlagMaskCommand);
									return true;
								case FIREFOX:
									pressKeyWithFlags(kVK_Tab, kCGEventFlagMaskControl);
									return true;
								default:
									break;
							}
						}
						default:
							break;
					}
					break;
				default:
					break;
			}
			break;
		case 3:
			if (directions[0] == DOWN && directions[1] == LEFT && directions[2] == UP) { // print email
				typeSting(&email);
				return true;
			}
			break;
		default:
			break;
	}
	return false;
}

static CGEventRef mouseEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
	// not thread safe, but it's always called in main thread
	NSEvent *mouseEvent;
	switch (type) {
		case kCGEventRightMouseDown:
			mouseEvent = [NSEvent eventWithCGEvent:event];
			[windowController handleMouseEvent:mouseEvent];
			mouseDownEvent = event;
			CFRetain(mouseDownEvent);
			lastLocation = mouseEvent.locationInWindow;
			break;
		case kCGEventRightMouseDragged:
			mouseEvent = [NSEvent eventWithCGEvent:event];
			[windowController handleMouseEvent:mouseEvent];
			if (mouseDraggedEvent) {
				CFRelease(mouseDraggedEvent);
			}
			mouseDraggedEvent = event;
			CFRetain(mouseDraggedEvent);
			updateDirections(mouseEvent);
			break;
		case kCGEventRightMouseUp: {
			mouseEvent = [NSEvent eventWithCGEvent:event];
			[windowController handleMouseEvent:mouseEvent];
			updateDirections(mouseEvent);
			if (!handleGesture()) {
				if (mouseDownEvent) {
					CGEventPost(kCGSessionEventTap, mouseDownEvent);
					if (mouseDraggedEvent) {
						CGEventPost(kCGSessionEventTap, mouseDraggedEvent);
					}
					CGEventPost(kCGSessionEventTap, event);
				}
			}
			if (mouseDownEvent) {
				CFRelease(mouseDownEvent);
			}
			if (mouseDraggedEvent) {
				CFRelease(mouseDraggedEvent);
			}
			mouseDownEvent = mouseDraggedEvent = NULL;
			directionLength = 0;
			break;
		}
		case kCGEventTapDisabledByTimeout:
			CGEventTapEnable(mouseEventTap, isEnable); // re-enable
			// pass through
		case kCGEventTapDisabledByUserInput: // will be useful if using CGEventTap to disable
			directionLength = 0;
			if (mouseDownEvent) {
				CGPoint location = CGEventGetLocation(mouseDownEvent);
				CGEventPost(kCGSessionEventTap, mouseDownEvent);
				CFRelease(mouseDownEvent);
				if (mouseDraggedEvent) {
					location = CGEventGetLocation(mouseDraggedEvent);
					CGEventPost(kCGSessionEventTap, mouseDraggedEvent);
					CFRelease(mouseDraggedEvent);
				}
				CGEventRef event = CGEventCreateMouseEvent(NULL, kCGEventRightMouseUp, location, kCGMouseButtonRight);
				CGEventPost(kCGSessionEventTap, event);
				CFRelease(event);
			}
			mouseDownEvent = mouseDraggedEvent = NULL;
			windowController.enable = isEnable;
			break;
		default:
			return event;
	}
	
	return NULL;
}

- (BOOL)toggleEnable {
	windowController.enable = isEnable = !isEnable;
	CGEventTapEnable(mouseEventTap, isEnable);
	return isEnable;
}

- (void)dealloc
{
	[super dealloc];
	[windowController release];
	[menuController release];
	if (username.string) {
		free(username.string);
	}
	if (password.string) {
		free(password.string);
	}
	if (email.string) {
		free(email.string);
	}
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	copyUnicodeString(NSLocalizedString(@"username", nil), &username);
	copyUnicodeString(NSLocalizedString(@"password", nil), &password);
	copyUnicodeString(NSLocalizedString(@"email", nil), &email);

	windowController = [[CanvasWindowController alloc] init];
	
	CGEventMask eventMask = CGEventMaskBit(kCGEventRightMouseDown) | CGEventMaskBit(kCGEventRightMouseDragged) | CGEventMaskBit(kCGEventRightMouseUp);
	mouseEventTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, eventMask, mouseEventCallback, NULL);
	CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mouseEventTap, 0);
	CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
	CFRelease(mouseEventTap);
	CFRelease(runLoopSource);
	isEnable = true;
	
	getFrontProcessPID();
}

@end
