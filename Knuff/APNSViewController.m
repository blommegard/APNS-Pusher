//
//  APNSViewController.m
//  APNS Pusher
//
//  Created by Simon Blommegard on 14/03/15.
//  Copyright (c) 2015 Bowtie. All rights reserved.
//

#import "APNSViewController.h"
#import "APNSSecIdentityType.h"
#import "APNSIdentityChooser.h"
#import "Constants.h"

#import "SBAPNS.h"

#import "APNSServiceBrowser.h"
#import "APNSDevicesViewController.h"
#import "APNSServiceDevice.h"

#import "APNSDocument.h"
#import "APNSItem.h"

#import "APNSidentityExporter.h"

#import "FBKVOController.h"

#import "pop.h"
#import <Fragaria/Fragaria.h>

@interface APNSViewController () <MGSFragariaTextViewDelegate, MGSDragOperationDelegate, APNSDevicesViewControllerDelegate, NSPopoverDelegate, NSTextViewDelegate, SBAPNSDelegate>
@property (nonatomic, strong) FBKVOController *KVOController;

@property (nonatomic, strong) SBAPNS *APNS;

@property (nonatomic, assign, readonly) NSString *identityName;

@property (weak) IBOutlet NSView *identityWrapperView;
@property (weak) IBOutlet NSView *identityView;

@property (weak) IBOutlet NSView *payloadView;

@property (nonatomic) BOOL showDevices; // current state of the UI

@property (weak) IBOutlet NSTextField *tokenTextField;
@property (weak) IBOutlet NSButton *devicesButton;

@property (nonatomic, strong, readonly) NSDictionary *payload;

@property (weak) IBOutlet MGSFragariaView *fragariaView;

@property (nonatomic, strong) NSPopover *devicesPopover;

@property (nonatomic) APNSItemMode mode; // current state of the UI
@property (weak) IBOutlet NSSegmentedControl *modeSegmentedControl;

@property (weak) IBOutlet NSSegmentedControl *prioritySegmentedControl; // Only 5 and 10

@property (nonatomic) BOOL showSandbox; // current state of the UI
@property (weak) IBOutlet NSSegmentedControl *sandboxSegmentedControl;
@end

@implementation APNSViewController


- (instancetype)initWithCoder:(NSCoder *)coder {
  if (self = [super initWithCoder:coder]) {
    self.KVOController = [FBKVOController controllerWithObserver:self];
    
    // sync with UI
    _showSandbox = YES;
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  [self updatePlaceholderToken];
  
  [APNSServiceBrowser browser].searching = YES;
  
  // It is layouted like this in the storyboard
  self.showDevices = YES;
  
  [self.KVOController observe:[APNSServiceBrowser browser]
                      keyPath:@"devices"
                      options:NSKeyValueObservingOptionNew
                        block:^(APNSViewController *observer, APNSServiceBrowser* object, NSDictionary *change) {
                          [observer devicesDidChange:NO];
                        }];
  
  [self devicesDidChange:YES];
  
  [[MGSUserDefaultsController sharedController] addFragariaToManagedSet:self.fragariaView];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(defaultTokenDidChange:) name:APNSDefaultTokenDidChangeNotification object:nil];
}

- (void)defaultTokenDidChange:(NSNotification *)notification
{
  [self updatePlaceholderToken];
}

- (void)updatePlaceholderToken
{
  NSString *defaultToken = [[NSUserDefaults standardUserDefaults] stringForKey:APNSDefaultTokenKey];
  if (defaultToken.length > 0) {
    self.tokenTextField.placeholderString = defaultToken;
  } else {
    self.tokenTextField.placeholderString = APNSPlaceholderToken;
  }
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark -

- (IBAction)exportIdentity:(id)sender {
  [APNSIdentityExporter exportIdentity:self.APNS.identity withPanelWindow:self.document.windowForSheet];
}

- (IBAction)changeMode:(NSSegmentedControl *)sender {
  APNSItemMode mode = sender.selectedSegment;

  if (mode != self.document.mode) {
    self.document.mode = mode;
  }
}

- (IBAction)presentDevices:(id)sender {
  NSStoryboard *storyboard = [NSStoryboard storyboardWithName:@"Main" bundle:nil];
  APNSDevicesViewController *viewController = [storyboard instantiateControllerWithIdentifier:@"Devices View Controller"];
  viewController.delegate = self;
  
  NSPopover *popover = [[NSPopover alloc] init];
  popover.contentViewController = viewController;
  
  popover.delegate = self;
  popover.animates = YES;
  popover.behavior = NSPopoverBehaviorTransient;
  [popover showRelativeToRect:[sender bounds] ofView:sender preferredEdge:NSMaxYEdge];
  
  self.devicesPopover = popover;
}

- (IBAction)chooseIdentity:(id)sender {
  APNSIdentityChooser *chooser = [APNSIdentityChooser new];
  [chooser displayWithWindow:self.view.window completion:^(SecIdentityRef selectedIdentity) {
    NSArray *topics;
    APNSSecIdentityType type = APNSSecIdentityGetType(selectedIdentity, &topics);
    [self setShowSandbox:(type == APNSSecIdentityTypeUniversal) animated:YES];

    [self willChangeValueForKey:@"identityName"];
    [self.APNS setIdentity:selectedIdentity];
    [self didChangeValueForKey:@"identityName"];
  }];
}

- (IBAction)changePriority:(NSSegmentedControl *)sender {
  APNSItemPriority priority = (sender.selectedSegment == 0) ? APNSItemPriorityLater:APNSItemPriorityImmediately;
  
  if (priority != self.document.priority) {
    self.document.priority = priority;
  }
}

- (IBAction)changeSandbox:(NSSegmentedControl *)sender {
  BOOL sandbox = (sender.selectedSegment == 1);
  
  if (sandbox != self.document.sandbox) {
    self.document.sandbox = sandbox;
  }
}

- (IBAction)push:(id)sender {
  // TODO: Check payload
  
//  uint8_t priority = 10;
//  
//  NSArray *APSKeys = [[self.payload objectForKey:@"aps"] allKeys];
//  if (APSKeys.count == 1 && [APSKeys.lastObject isEqualTo:@"content-available"]) {
//    priority = 5;
//  }
  
  
  if ([self document].mode == APNSItemModeCustom && self.APNS.identity != NULL) {
    
    NSArray *topics;
    APNSSecIdentityType type = APNSSecIdentityGetType(self.APNS.identity, &topics);

    BOOL sandbox = NO;
    
    if (type == APNSSecIdentityTypeDevelopment) {
      sandbox = YES;
    } else if (type == APNSSecIdentityTypeUniversal) {
      sandbox = [self document].sandbox;
    }
    
    [self.APNS pushPayload:self.payload
                   toToken:[self preparedToken]
                 withTopic:topics.firstObject
                  priority:self.document.priority
                 inSandbox:sandbox];
  } else if ([self document].mode == APNSItemModeKnuff) {
    // Grab cert
    
    NSString *thePath = [[NSBundle mainBundle] pathForResource:@"Knuff" ofType:@"p12"];
    NSData *PKCS12Data = [[NSData alloc] initWithContentsOfFile:thePath] ;
    
    CFArrayRef items = CFArrayCreate(NULL, 0, 0, NULL);
    OSStatus ret = SecPKCS12Import(
                                   (__bridge CFDataRef)PKCS12Data,
                                   (__bridge CFDictionaryRef)@{(id)kSecImportExportPassphrase:@""},
                                   &items);
    
    if (ret != errSecSuccess) {
      // :(
    }
    
    NSDictionary *firstItem = [(__bridge_transfer NSArray *)items firstObject];
    
    
    SecIdentityRef identity = (__bridge SecIdentityRef)(firstItem[(__bridge id)kSecImportItemIdentity]);
    
    self.APNS.identity = identity;
    
    [self.APNS pushPayload:self.payload
                   toToken:[self preparedToken]
                 withTopic:@"com.madebybowtie.Knuff-iOS"
                  priority:self.document.priority
                 inSandbox:NO];
  } else {
    //    NSAlert *alert = [NSAlert new];
    //    [alert addButtonWithTitle:@"OK"];
    //    alert.messageText = @"Missing identity";
    //    alert.informativeText = @"You have not choosen an identity for signing the notification.";
    //
    //    [alert beginSheetModalForWindow:self.windowController.window completionHandler:nil];
  }
}

- (void)modeDidChange:(BOOL)initial {
  // Update UI
  [self setMode:self.document.mode animated:!initial];
  
  // Clear identity
  if (self.document.mode == APNSItemModeKnuff) {
    [self willChangeValueForKey:@"identityName"];
    self.APNS.identity = NULL;
    [self didChangeValueForKey:@"identityName"];
  }
}

- (void)devicesDidChange:(BOOL)initial {
  APNSServiceBrowser *browser = [APNSServiceBrowser browser];

  NSLog(@"%@", @(browser.devices.count));
  
  BOOL changed = NO;
  
  CGFloat devicesButtonAlpha = self.devicesButton.alphaValue;
  NSRect textFieldRect = self.tokenTextField.frame;
  
  // Hide
  if (self.showDevices && browser.devices.count == 0) {
    devicesButtonAlpha = 0;
    textFieldRect.size.width = self.payloadView.bounds.size.width - textFieldRect.origin.x;
    
    changed = YES;
  }
  // Show
  else if (!self.showDevices && browser.devices.count > 0) {
    devicesButtonAlpha = 1;
    textFieldRect.size.width = self.payloadView.bounds.size.width - textFieldRect.origin.x - self.devicesButton.bounds.size.width - 8;

    changed = YES;
  }
  
  if (changed) {
    self.showDevices = !self.showDevices;
    
    if (initial) {
      self.devicesButton.alphaValue = devicesButtonAlpha;
      self.tokenTextField.frame = textFieldRect;
      self.devicesButton.hidden = !self.showDevices;
    } else {
      if (self.showDevices) {
        self.devicesButton.hidden = NO;
      }
      
      POPSpringAnimation *animation = [POPSpringAnimation animationWithPropertyNamed:kPOPViewAlphaValue];
      animation.toValue = @(devicesButtonAlpha);
      animation.completionBlock = ^(POPAnimation *ani, BOOL finished) {
        if (!self.showDevices) {
          self.devicesButton.hidden = YES;
        }
      };
      
      [self.devicesButton pop_addAnimation:animation forKey:nil];
      
      animation = [POPSpringAnimation animationWithPropertyNamed:kPOPViewFrame];
      animation.toValue = [NSValue valueWithRect:textFieldRect];
      
      [self.tokenTextField pop_addAnimation:animation forKey:nil];
    }
  }
}

- (void)priorityDidChange {
  APNSItemPriority priority = self.document.priority;
  
  [self.prioritySegmentedControl setSelectedSegment:(priority == APNSItemPriorityLater)?0:1];
}

- (void)sandboxDidChange {
  BOOL sandbox = self.document.sandbox;
  
  [self.sandboxSegmentedControl setSelectedSegment:sandbox?1:0];
}

#pragma mark -

- (void)setMode:(APNSItemMode)mode {
  [self setMode:mode animated:NO];
}

- (void)setMode:(APNSItemMode)mode animated:(BOOL)animated {
  if (self.mode != mode) {
    _mode = mode;
    
    BOOL knuff = (mode == APNSItemModeKnuff);
    
    // Correct segment
    self.modeSegmentedControl.selectedSegment = mode;
    
    // Diff
    CGFloat diff = 8 + self.identityWrapperView.bounds.size.height;
    
    // Hide / Show identity
    
    CGFloat identityWrapperViewAlphaVelue = knuff ? 0:1;
    
    NSRect windowFrame = self.view.window.frame;
    windowFrame.size.height = knuff ?
      (windowFrame.size.height - diff):
      (windowFrame.size.height + diff);
    
    windowFrame.origin.y = knuff ?
      (windowFrame.origin.y + diff):
      (windowFrame.origin.y - diff);
    
    if (!animated) {
      self.identityWrapperView.alphaValue = identityWrapperViewAlphaVelue;
      
      NSAutoresizingMaskOptions options = self.payloadView.autoresizingMask;
      self.payloadView.autoresizingMask = NSViewNotSizable;
      
      [self.view.window setFrame:windowFrame display:NO];
      
      self.payloadView.autoresizingMask = options;
    } else {
      if (!knuff) {
        self.identityWrapperView.hidden = NO;
      }
      
      POPSpringAnimation *animation = [POPSpringAnimation animationWithPropertyNamed:kPOPViewAlphaValue];
      
      [animation setCompletionBlock:^(POPAnimation *ani, BOOL fin) {
        if (knuff) {
          self.identityWrapperView.hidden = YES;
        }
      }];
      
      animation.toValue = @(identityWrapperViewAlphaVelue);
      [self.identityWrapperView pop_addAnimation:animation forKey:nil];
      
      // Ajust window
      
      // Make sure to move the payload with it
      NSAutoresizingMaskOptions options = self.payloadView.autoresizingMask;
      self.payloadView.autoresizingMask = NSViewNotSizable;
      
      animation = [POPSpringAnimation animationWithPropertyNamed:kPOPWindowFrame];
      
      [animation setCompletionBlock:^(POPAnimation *ani, BOOL fin) {
        self.payloadView.autoresizingMask = options;
      }];
      
      animation.toValue = [NSValue valueWithRect:windowFrame];
      [self.view.window pop_addAnimation:animation forKey:nil];
    }
  }
}

- (void)setShowSandbox:(BOOL)showSandbox {
  [self setShowSandbox:showSandbox animated:NO];
}

- (void)setShowSandbox:(BOOL)showSandbox animated:(BOOL)animated {
  if (self.showSandbox != showSandbox) {
    _showSandbox = showSandbox;
    
    // Diff
    CGFloat diff = 8 + self.sandboxSegmentedControl.bounds.size.width;
    
    // Hide / Show sandbox
    
    CGFloat sandboxSegmentedControlAlphaVelue = _showSandbox ? 1:0;
    
    NSRect identityViewFrame = self.identityView.frame;
    identityViewFrame.size.width = _showSandbox ?
    (identityViewFrame.size.width - diff):
    (identityViewFrame.size.width + diff);
    
    if (!animated) {
      self.sandboxSegmentedControl.alphaValue = sandboxSegmentedControlAlphaVelue;
      self.identityView.frame = identityViewFrame;
    } else {
      if (_showSandbox) {
        self.sandboxSegmentedControl.hidden = NO;
      }
      
      POPSpringAnimation *animation = [POPSpringAnimation animationWithPropertyNamed:kPOPViewAlphaValue];
      
      [animation setCompletionBlock:^(POPAnimation *ani, BOOL fin) {
        if (!_showSandbox) {
          self.sandboxSegmentedControl.hidden = YES;
        }
      }];
      
      animation.toValue = @(sandboxSegmentedControlAlphaVelue);
      [self.sandboxSegmentedControl pop_addAnimation:animation forKey:nil];
      
      // Ajust view
      animation = [POPSpringAnimation animationWithPropertyNamed:kPOPViewFrame];
      
      animation.toValue = [NSValue valueWithRect:identityViewFrame];
      [self.identityView pop_addAnimation:animation forKey:nil];
    }
  }
}

#pragma mark -

- (SBAPNS *)APNS {
  if (!_APNS) {
    _APNS = [SBAPNS new];
    _APNS.delegate = self;
  }
  return _APNS;
}

#pragma mark -

- (void)setRepresentedObject:(APNSDocument *)representedObject {
  [self.KVOController unobserve:self.representedObject];

  super.representedObject = representedObject;
  
  [self.KVOController observe:representedObject
                      keyPath:@"token"
                      options:(NSKeyValueObservingOptionNew|NSKeyValueObservingOptionInitial)
                        block:^(APNSViewController *observer, APNSDocument *object, NSDictionary *change) {
                          
                          if (object.token) {
                            [observer.tokenTextField setStringValue:object.token];
                          } else {
                            [observer.tokenTextField setStringValue:@""];
                          }
                        }];
  
  [self.KVOController observe:representedObject
                      keyPath:@"mode"
                      options:NSKeyValueObservingOptionNew
                        block:^(APNSViewController *observer, APNSDocument *object, NSDictionary *change) {
                          [observer modeDidChange:NO];
                        }];
  
  [self modeDidChange:YES];
  
  [self.KVOController observe:representedObject
                      keyPath:@"priority"
                      options:(NSKeyValueObservingOptionNew|NSKeyValueObservingOptionInitial)
                        block:^(APNSViewController *observer, APNSDocument *object, NSDictionary *change) {
                          [observer priorityDidChange];
                        }];
  
  [self.KVOController observe:representedObject
                      keyPath:@"sandbox"
                      options:(NSKeyValueObservingOptionNew|NSKeyValueObservingOptionInitial)
                        block:^(APNSViewController *observer, APNSDocument *object, NSDictionary *change) {
                          [observer sandboxDidChange];
                        }];
  
  [self setShowSandbox:NO animated:NO];
  
  self.fragariaView.syntaxColoured = YES;
  self.fragariaView.showsLineNumbers = YES;
  self.fragariaView.syntaxDefinitionName = @"JavaScript";
  self.fragariaView.textViewDelegate = self;
  
  [self.fragariaView setString:representedObject.payload];

  [representedObject setUndoManager:[self.fragariaView.textView undoManager]];
}

#pragma mark -

- (NSDictionary *)payload {
  NSData *data = [self.fragariaView.string dataUsingEncoding:NSUTF8StringEncoding];
  
  if (data) {
    NSError *error;
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    
    if (payload && [payload isKindOfClass:[NSDictionary class]])
      return payload;
  }
  
  return nil;
}

- (NSString *)preparedToken {
  NSString *token = self.tokenTextField.stringValue;
  if (token.length == 0) {
    token = [[NSUserDefaults standardUserDefaults] stringForKey:APNSDefaultTokenKey];
  }
  
  NSCharacterSet *removeCharacterSet = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
  token = [[token componentsSeparatedByCharactersInSet:removeCharacterSet] componentsJoinedByString:@""];
  return [token lowercaseString];
}

#pragma mark -

- (NSString *)identityName {
  if (self.APNS.identity == NULL)
    return @"Choose an identity";
  else {
    SecCertificateRef cert = NULL;
    if (noErr == SecIdentityCopyCertificate(self.APNS.identity, &cert)) {
      CFStringRef commonName = NULL;
      SecCertificateCopyCommonName(cert, &commonName);
      CFRelease(cert);
      
      return (__bridge_transfer NSString *)commonName;
    }
  }
  return @"";
}

- (APNSDocument *)document {
  return self.representedObject;
}

#pragma mark - NSUserInterfaceValidations

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem {
  if (anItem.action == @selector(exportIdentity:)) {
    return (self.APNS.identity != NULL);
  }
  
  return NO;
}

#pragma mark - NSTextDelegate

- (void)textDidChange:(NSNotification *)notification {
  [self.document setPayload:self.fragariaView.string];
}

#pragma mark - NSControlSubclassNotifications

- (void)controlTextDidChange:(NSNotification *)notification {
  [self.document setToken:self.tokenTextField.stringValue];
}

#pragma mark - APNSDevicesViewControllerDelegate

- (void)deviceViewController:(APNSDevicesViewController *)viewController didSelectDevice:(APNSServiceDevice *)device {
  self.tokenTextField.stringValue = device.token;
  
  [self.devicesPopover close];
  
  [self.document setToken:self.tokenTextField.stringValue];
}

#pragma mark - NSPopoverDelegate

- (void)popoverDidClose:(NSNotification *)notification {
  self.devicesPopover.contentViewController = nil;
  self.devicesPopover = nil;
}

#pragma mark - SBAPNSDelegate

- (void)APNS:(SBAPNS *)APNS didRecieveStatus:(NSInteger)statusCode reason:(NSString *)reason forID:(NSString *)ID {
  NSAlert *alert = [NSAlert new];
  [alert addButtonWithTitle:@"OK"];
  alert.messageText = @"Error delivering notification";
  alert.informativeText = [NSString stringWithFormat:@"%ld: %@", (long)statusCode, reason];
  
  [alert beginSheetModalForWindow:self.document.windowForSheet completionHandler:nil];
}

@end
