//
//  SenPlayerHack.m
//  dylib_dobby_hook
//
//  Created by ooooooio on 2025/7/4.
//

#import <Foundation/Foundation.h>
#import "MemoryUtils.h"
#import <objc/runtime.h>
#import "HackProtocolDefault.h"
#import "common_ret.h"

@interface SenPlayerHack : HackProtocolDefault



@end


@implementation SenPlayerHack

+ (NSString *)getAppName {
    return @"com.wuziqi.SenPlayer";
}

+ (NSString *)getSupportAppVersion {
    return @"6"; // 6.1.3
}

//static OrigAppStorageWrappedValueGetter orig_AppStorage_getter = NULL;
//static SWIFTCALL void hk_AppStorage_wrappedValue_getter(
//    SWIFT_INDIRECT_RESULT void *result,
//    void *self,
//    void *typeMetadata
//) {
//    NSString *key = decodeSwiftString((uint8_t *)self + 0x10);
//    NSLogger(@"[AppStorage_getter] self=%@ key=%@", self, key);
//    if (orig_AppStorage_getter)
//        orig_AppStorage_getter(result, self, typeMetadata);
//}

// MARK: - AppStorage.init<A>(wrappedValue:_:store:)(0, 'pus', 0xE300000000000000LL, 0); // -> Bool
// x86_64: RDI=wrappedValue, RSI=_countAndFlagsBits, RDX=_object, RCX=store, RAX=box ptr
static void *(*orig_AppStorageBoolInit)(BOOL, uintptr_t, uintptr_t, void *) = NULL;
static void *hk_AppStorageBoolInit(BOOL wrappedValue, uintptr_t word0, uintptr_t word1, void *store) {
    SwiftString ss = {word0, word1};
    NSString *key = decodeSwiftString(&ss);
    NSLogger(@"[AppStorage_init:Bool] key=%@ raw=0x%llx_0x%llx defaultValue=%d store=%p",
             key ?: @"(nil)", (uint64_t)word0, (uint64_t)word1, wrappedValue, store);
    BOOL defaultValue = wrappedValue;
    if (key) {
        NSSet *overrideKeys = [NSSet setWithObjects:@"sup", @"upp", @"iop", @"tvp", @"map", nil];
        if ([overrideKeys containsObject:key]) {
            defaultValue = YES;
            NSLogger(@"[AppStorage_init:Bool] ⭐️ override key=%@ defaultValue=0->1", key);
        }
    }
    return orig_AppStorageBoolInit(defaultValue, word0, word1, store);
}

- (BOOL)hack {
    
    [MemoryUtils hookClassMethod:
         NSClassFromString(@"NSUbiquitousKeyValueStore")
                   originalSelector:NSSelectorFromString(@"defaultStore")
                      swizzledClass:[self class]
                   swizzledSelector:@selector(hook_defaultStore)
    ];

    [MemoryUtils hookClassMethod:
        NSClassFromString(@"CKContainer")
                  originalSelector:NSSelectorFromString(@"containerWithIdentifier:")
                     swizzledClass:[self class]
                  swizzledSelector:@selector(hook_containerWithIdentifier: )
    ];
    [MemoryUtils hookClassMethod:
        NSClassFromString(@"CKContainer")
                  originalSelector:NSSelectorFromString(@"defaultContainer")
                     swizzledClass:[self class]
                  swizzledSelector:@selector(hook_defaultContainer)

    ];
    
    // formalProDate
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@"com.wuziqi.SenPlayer.LifeTimePro" forKey:@"ProId"];
    [defaults setObject:@YES forKey:@"kFont"];
    [defaults synchronize];

//    tiny_interpose(
//        [MemoryUtils indexForImageWithName:@"SenPlayer"],
//        "_$s7SwiftUI10AppStorageV12wrappedValuexvg",
//        (void *)hk_AppStorage_wrappedValue_getter,
//        (void **)&orig_AppStorage_getter
//    );

    tiny_interpose(
        [MemoryUtils indexForImageWithName:@"SenPlayer"],
        "_$s7SwiftUI10AppStorageV12wrappedValue_5storeACySbGSb_SSSo14NSUserDefaultsCSgtcSbRszlufC",
        (void *)hk_AppStorageBoolInit,
        (void **)&orig_AppStorageBoolInit
    );

    // _OBJC_IVAR_$__TtC9SenPlayer16StoreKit2Manager_viewShare
    // _OBJC_IVAR_$__TtC9SenPlayer11ViewPublish__formalProDate
    #if defined(__arm64__) || defined(__aarch64__)
    NSString *getProDays = @"E9 23 BA 6D FA 67 01 A9 F8 5F 02 A9 F6 57 03 A9 F4 4F 04 A9 FD 7B 05 A9 FD 43 01 91 FF 43 00 D1 08 1C A0 4E ?? ?? ?? 90 ?? ?? ?? 91 ?? ?? ?? 90 ?? ?? ?? 91 ?? ?? ?? 97";
#elif defined(__x86_64__)
    NSString *getProDays = @"55 48 89 E5 41 57 41 56 41 55 41 54 53 48 83 EC 38 F2 0F 11 45 B0 48 8D 3D ?? ?? ?? ?? 48 8D 35 ?? ?? ?? ?? E8 ?? ?? ?? ?? 49 89 C4 48 8B 40 F8 48 8B 40 40 E8 ?? ?? ?? ??";
#endif
    [MemoryUtils hookWithMachineCode:@"/Contents/MacOS/SenPlayer"
                         machineCode:getProDays
                           fake_func:(void *)ret1
                               count:1
    ];
    return YES;
}

@end
