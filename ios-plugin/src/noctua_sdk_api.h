// Objective-C view of the NoctuaSDK Swift class (`@objc public class Noctua`).
//
// The plugin does not import <NoctuaSDK/NoctuaSDK-Swift.h>; it looks the class up
// at runtime (NSClassFromString) and messages it through this protocol. That keeps
// the plugin binary independent of the NoctuaSDK pod version — the pod is linked
// into the exported Xcode project by scripts/setup_xcode.rb.
//
// Selectors follow Swift's @objc naming for the signatures in
// ios/NoctuaSDK/Sources/Noctua.swift (noctua-native-sdk ios-sdk-v0.40.1).
// GodotNoctua verifies every selector at start-up and logs any that are missing.

#ifndef GODOT_NOCTUA_SDK_API_H
#define GODOT_NOCTUA_SDK_API_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol NoctuaSDKAPI <NSObject>

// initNoctua(verifyPurchasesOnServer:useStoreKit1:) throws — not an ObjC "init"
// method despite the name (the generated header marks it the same way).
+ (BOOL)initNoctuaWithVerifyPurchasesOnServer:(BOOL)verifyPurchasesOnServer
                                 useStoreKit1:(BOOL)useStoreKit1
                                        error:(NSError *_Nullable *_Nullable)error
    __attribute__((objc_method_family(none)));

// Tracking
+ (void)trackCustomEvent:(NSString *)eventName payload:(NSDictionary<NSString *, id> *)payload;
+ (void)trackPurchaseWithOrderId:(NSString *)orderId
                          amount:(double)amount
                        currency:(NSString *)currency
                    extraPayload:(NSDictionary<NSString *, id> *)extraPayload;
+ (void)trackAdRevenueWithSource:(NSString *)source
                         revenue:(double)revenue
                        currency:(NSString *)currency
                    extraPayload:(NSDictionary<NSString *, id> *)extraPayload;

// Session
+ (void)setSessionTagWithTag:(NSString *)tag;
+ (nullable NSString *)getSessionTags;
+ (void)setSessionExtraParamsWithPayload:(NSDictionary<NSString *, id> *)payload;

// Experiments
+ (void)setExperimentWithExperiment:(NSString *)experiment;
+ (nullable NSString *)getExperiment;
+ (void)setGeneralExperimentWithExperiment:(NSString *)experiment;
+ (nullable NSString *)getGeneralExperimentWithExperimentKey:(NSString *)experimentKey;

// Network state
+ (void)onOnline;
+ (void)onOffline;

// Diagnostics
+ (void)getAdjustSdkVersionWithCompletion:(void (^)(NSString *_Nullable version))completion;

@end

NS_ASSUME_NONNULL_END

#endif // GODOT_NOCTUA_SDK_API_H
