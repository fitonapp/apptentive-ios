//
//  ApptentiveEngagementBackend.m
//  Apptentive
//
//  Created by Peter Kamb on 8/21/13.
//  Copyright (c) 2013 Apptentive, Inc. All rights reserved.
//

#import "ApptentiveBackend+Engagement.h"
#import "ApptentiveBackend.h"
#import "ApptentiveInteraction.h"
#import "ApptentiveInteractionInvocation.h"
#import "Apptentive_Private.h"
#import "ApptentiveBackend+Metrics.h"
#import "ApptentiveInteractionController.h"
#import "ApptentiveEngagement.h"
#import "ApptentiveEngagementManifest.h"

NSString *const ATEngagementCachedInteractionsExpirationPreferenceKey = @"ATEngagementCachedInteractionsExpirationPreferenceKey";

NSString *const ATEngagementCodePointHostAppVendorKey = @"local";
NSString *const ATEngagementCodePointHostAppInteractionKey = @"app";
NSString *const ATEngagementCodePointApptentiveVendorKey = @"com.apptentive";
NSString *const ATEngagementCodePointApptentiveAppInteractionKey = @"app";

NSString *const ApptentiveEngagementMessageCenterEvent = @"show_message_center";


@implementation ApptentiveBackend (Engagement)

- (BOOL)canShowInteractionForLocalEvent:(NSString *)event {
	NSString *codePoint = [[ApptentiveInteraction localAppInteraction] codePointForEvent:event];

	return [self canShowInteractionForCodePoint:codePoint];
}

- (BOOL)canShowInteractionForCodePoint:(NSString *)codePoint {
	ApptentiveInteraction *interaction = [self interactionForEvent:codePoint];

	return (interaction != nil);
}

- (ApptentiveInteraction *)interactionForInvocations:(NSArray *)invocations {
	NSString *interactionID = nil;

	for (NSObject *invocationOrDictionary in invocations) {
		ApptentiveInteractionInvocation *invocation = nil;

		// Allow parsing of ATInteractionInvocation and NSDictionary invocation objects
		if ([invocationOrDictionary isKindOfClass:[ApptentiveInteractionInvocation class]]) {
			invocation = (ApptentiveInteractionInvocation *)invocationOrDictionary;
		} else if ([invocationOrDictionary isKindOfClass:[NSDictionary class]]) {
			invocation = [ApptentiveInteractionInvocation invocationWithJSONDictionary:((NSDictionary *)invocationOrDictionary)];
		} else {
			ApptentiveLogError(@"Attempting to parse an invocation that is neither an ATInteractionInvocation or NSDictionary.");
		}

		if (invocation && [invocation isKindOfClass:[ApptentiveInteractionInvocation class]]) {
			if ([invocation criteriaAreMetForSession:self.session]) {
				interactionID = invocation.interactionID;
				break;
			}
		}
	}

	ApptentiveInteraction *interaction = nil;
	if (interactionID) {
		interaction = [self interactionForIdentifier:interactionID];
	}

	return interaction;
}

- (ApptentiveInteraction *)interactionForIdentifier:(NSString *)identifier {
	return self.manifest.interactions[identifier];
}

- (ApptentiveInteraction *)interactionForEvent:(NSString *)event {
	NSArray *invocations = self.manifest.targets[event];
	ApptentiveInteraction *interaction = [self interactionForInvocations:invocations];

	return interaction;
}

+ (NSString *)stringByEscapingCodePointSeparatorCharactersInString:(NSString *)string {
	// Only escape "%", "/", and "#".
	// Do not change unless the server spec changes.
	NSMutableString *escape = [string mutableCopy];
	[escape replaceOccurrencesOfString:@"%" withString:@"%25" options:NSLiteralSearch range:NSMakeRange(0, escape.length)];
	[escape replaceOccurrencesOfString:@"/" withString:@"%2F" options:NSLiteralSearch range:NSMakeRange(0, escape.length)];
	[escape replaceOccurrencesOfString:@"#" withString:@"%23" options:NSLiteralSearch range:NSMakeRange(0, escape.length)];

	return escape;
}

+ (NSString *)codePointForVendor:(NSString *)vendor interactionType:(NSString *)interactionType event:(NSString *)event {
	NSString *encodedVendor = [[self class] stringByEscapingCodePointSeparatorCharactersInString:vendor];
	NSString *encodedInteractionType = [[self class] stringByEscapingCodePointSeparatorCharactersInString:interactionType];
	NSString *encodedEvent = [[self class] stringByEscapingCodePointSeparatorCharactersInString:event];

	NSString *codePoint = [NSString stringWithFormat:@"%@#%@#%@", encodedVendor, encodedInteractionType, encodedEvent];

	return codePoint;
}

- (BOOL)engageApptentiveAppEvent:(NSString *)event {
	return [[ApptentiveInteraction apptentiveAppInteraction] engage:event fromViewController:nil];
}

- (BOOL)engageLocalEvent:(NSString *)event userInfo:(NSDictionary *)userInfo customData:(NSDictionary *)customData extendedData:(NSArray *)extendedData fromViewController:(UIViewController *)viewController {
	return [[ApptentiveInteraction localAppInteraction] engage:event fromViewController:viewController userInfo:userInfo customData:customData extendedData:extendedData];
}

- (BOOL)engageCodePoint:(NSString *)codePoint fromInteraction:(ApptentiveInteraction *)fromInteraction userInfo:(NSDictionary *)userInfo customData:(NSDictionary *)customData extendedData:(NSArray *)extendedData fromViewController:(UIViewController *)viewController {
	ApptentiveLogInfo(@"Engage Apptentive event: %@", codePoint);
	if (![self isReady]) {
		return NO;
	}

	[self addMetricWithName:codePoint fromInteraction:fromInteraction info:userInfo customData:customData extendedData:extendedData];

	[self codePointWasSeen:codePoint];
	[self codePointWasEngaged:codePoint];

	BOOL didEngageInteraction = NO;

	ApptentiveInteraction *interaction = [self interactionForEvent:codePoint];
	if (interaction) {
		ApptentiveLogInfo(@"--Running valid %@ interaction.", interaction.type);

		if (viewController == nil) {
			viewController = [Apptentive.shared viewControllerForInteractions];
		}

		if (viewController == nil || !viewController.isViewLoaded || viewController.view.window == nil) {
			ApptentiveLogError(@"Attempting to present interaction on a view controller whose view is not visible in a window.");
			return NO;
		}

		[self presentInteraction:interaction fromViewController:viewController];

		[self interactionWasEngaged:interaction];
		didEngageInteraction = YES;
	}

	return didEngageInteraction;
}

- (void)codePointWasSeen:(NSString *)codePoint {
	[self.session.engagement warmCodePoint:codePoint];
}

- (void)codePointWasEngaged:(NSString *)codePoint {
	[self.session.engagement engageCodePoint:codePoint];
}

- (void)interactionWasSeen:(NSString *)interactionID {
	[self.session.engagement warmInteraction:interactionID];
}

- (void)interactionWasEngaged:(ApptentiveInteraction *)interaction {
	[self.session.engagement engageInteraction:interaction.identifier];
}

- (void)presentInteraction:(ApptentiveInteraction *)interaction fromViewController:(UIViewController *)viewController {
	if (!interaction) {
		ApptentiveLogError(@"Attempting to present an interaction that does not exist!");
		return;
	}

	if (![[NSThread currentThread] isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self presentInteraction:interaction fromViewController:viewController];
		});
		return;
	}

	if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
		// Only present interaction UI in Active state.
		return;
	}

	ApptentiveInteractionController *controller = [ApptentiveInteractionController interactionControllerWithInteraction:interaction];

	[controller presentInteractionFromViewController:viewController];
}

@end
