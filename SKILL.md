---
name: dylib-dobby-hook
description: Dylib injection hook framework for macOS/iOS. Provides C function hooking (tiny_hook), dyld symbol interposition (tiny_interpose), symbol resolution (symtbl_solve/symexp_solve/symstub_solve), memory patching (write_mem), Objective-C method swizzling (MemoryUtils), and Swift ABI-compatible hooking (SWIFTCALL/SWIFT_CONTEXT attributes).
version: 1.0
language: en
tags: [dylib, dobby, hook, macOS, iOS, injection, tinyhook, MemoryUtils, Swift]
---

# Dylib Dobby Hook

Project entry point: `+[dylib_dobby_hook load] -> [Constant doHack]`.
Extension pattern: subclass `HackProtocolDefault`, implement `+getAppName`, `+getSupportAppVersion`, `-hack`.

## Common Files

| File | Contents |
|------|----------|
| `tinyhook.h` | `tiny_hook`, `tiny_interpose`, `symtbl_solve`, `symexp_solve`, `symstub_solve`, `write_mem` |
| `MemoryUtils.h` | OC method hook, signature scan, address translation utilities |
| `CommonRetOC.m` | `ret0`/`ret1`/`ret` stubs, CloudKit/Keychain/SecCode hooks |
| `mac/apps/*.m`, `ios/apps/*.m` | Reference app hook implementations |

## Adding a New App Hook

Create `mac/apps/XXXHack.m` (macOS) or `ios/apps/XXXHack.m` (iOS):

```objc
@interface XXXHack : HackProtocolDefault
@end

@implementation XXXHack

+ (NSString *)getAppName { return @"com.example.app"; }
+ (NSString *)getSupportAppVersion { return @"1."; } // prefix match; @"" for any version

- (BOOL)hack {
    // hook code here
    return YES;
}

@end
```

Override `+shouldInject:` to customize injection condition (default: bundle ID prefix match):

```objc
+ (BOOL)shouldInject:(NSString *)target {
    return [MemoryUtils indexForImageWithName:@"Paddle"] > 0;
}
```

## Hooking C Functions

### Target Resolution

| Strategy | API | When to Use |
|----------|-----|-------------|
| Direct symbol | `tiny_hook((void*)func, hk, &orig)` | Function linked into current image |
| Symbol table | `symtbl_solve(img, name)` → `tiny_hook(...)` | Symbol name known, target in another image |
| Export table | `symexp_solve(img, name)` → `tiny_hook(...)` | Exported symbols only |
| Stub / lazy | `symstub_solve(img, name)` → `tiny_hook(...)` | Lazy-bound Swift stubs |
| Static VA | `[MemoryUtils getPtrFromAddress:path targetFunctionAddress:va]` | IDA/Hopper static address |
| File offset | `[MemoryUtils getPtrFromGlobalOffset:path globalFunOffset:]` | Mach-O file offset |
| Signature scan | `[MemoryUtils getPtrFromMachineCode:path machineCode:pattern]` | Stripped symbols, byte pattern |

### General Pattern

```objc
static int (*orig_func)(int, pid_t, caddr_t, int);
static int hk_func(int request, pid_t pid, caddr_t addr, int data) {
    if (request == PT_DENY_ATTACH) return 0;
    return orig_func ? orig_func(request, pid, addr, data) : 0;
}
// tiny_hook((void *)ptrace, (void *)hk_func, (void *)&orig_func);
```

Shortcuts:
- Return constant: `tiny_hook((void *)addr, (void *)ret1, NULL);`
- Multiple signature matches: `[MemoryUtils hookWithMachineCode:... fake_func:(void *)ret count:N];`

### Interpose (dyld Lazy Binding)

For Swift global variable getters or targets that resist inline hooking:

```objc
typedef void (*OrigAccess)(SWIFT_CONTEXT void *, void *, void *) SWIFTCALL;
static OrigAccess orig_access;

static SWIFTCALL void hk_access(
    SWIFT_CONTEXT void *registrar, void *subject, void *keyPath
) {
    if (orig_access) orig_access(registrar, subject, keyPath);
}

// int img = [MemoryUtils indexForImageWithName:@"Target"];
// tiny_interpose(img, "_symbol_name", (void *)hk_access, (void **)&orig_access);
```

## Hooking ObjC Methods

Use `MemoryUtils hookInstanceMethod:` / `hookClassMethod:`:

```objc
static IMP orig_viewDidLoad;

- (void)hk_viewDidLoad {
    NSLogger(@"called hk_viewDidLoad self=%@", self);
    if (orig_viewDidLoad)
        ((void (*)(id, SEL))orig_viewDidLoad)(self, _cmd);
}

- (BOOL)hack {
    Class cls = objc_getClass("TargetModule.ViewController");
    if (!cls) return NO;
    orig_viewDidLoad = [MemoryUtils hookInstanceMethod:cls
                                      originalSelector:NSSelectorFromString(@"viewDidLoad")
                                         swizzledClass:[self class]
                                      swizzledSelector:NSSelectorFromString(@"hk_viewDidLoad")];
    return YES;
}
```

Class methods use `hookClassMethod:` with identical parameter semantics.

Fallback for recursive hooking — replace IMP directly via `tiny_hook`:

```objc
Method m = class_getInstanceMethod(cls, sel);
tiny_hook((void *)method_getImplementation(m), (void *)hk_func, (void *)&orig_func);
```

## Hooking Swift Functions

Swift uses a custom calling convention (`swiftcall`). Use `common_ret.h` macros on C hook functions to match the Swift ABI.

### Register Map

| Macro | Register | Purpose |
|-------|----------|---------|
| `SWIFTCALL` (func attr) | — | Synchronous Swift calling convention |
| `SWIFTASYNCCALL` (func attr) | — | Async Swift calling convention |
| `SWIFT_INDIRECT_RESULT` (param attr) | X8 | Large struct / tuple indirect return |
| `SWIFT_CONTEXT` (param attr) | X20 | `self` / closure context |
| `SWIFT_ERROR_RESULT` (param attr) | X21 | `throws` error pointer |
| `SWIFT_ASYNC_CONTEXT` (param attr) | X22 | Async continuation context |

X8 is the standard ARM64 AAPCS indirect result register (also used by C/ObjC). X20/X21/X22 are Swift-specific callee-saved registers; each is occupied only when the function has the corresponding semantic (instance method, throws, async).

### Example

```objc
// Published.subscript.getter — indirect result via X8
typedef void (*OrigPublishedGetter)(
    SWIFT_INDIRECT_RESULT void *result, void *instance,
    void *wrapped, void *storage
) SWIFTCALL;

static SWIFTCALL void hook_sub_get(
    SWIFT_INDIRECT_RESULT void *result, void *instance,
    void *wrapped, void *storage
) {
    if (orig_sub_get) orig_sub_get(result, instance, wrapped, storage);
    id obj = (__bridge id)instance;
    if ([obj isKindOfClass:NSClassFromString(@"Target.LicenseManager")]) {
        *(volatile uint8_t *)result = 1;
    }
}
```

Swift symbols should be resolved via `symstub_solve` (see Target Resolution table).

## Common Stubs

Provided by `CommonRetOC.m` via `HackProtocolDefault` inheritance:

| Call | Effect |
|------|--------|
| `[self hook_AllCloudKit]` | Mocks CKContainer, NSUbiquitousKeyValueStore |
| `[self hook_AllSecItem]` | Intercepts SecItemAdd/Update/Delete/CopyMatching |
| `[self hook_AllSecCode:@"TEAMID1234"]` | Forges TeamIdentifier in code signing checks |

## Direct Memory Patch

Use `write_mem` only when instructions are short and architecture is confirmed:

```objc
#if defined(__arm64__) || defined(__aarch64__)
uint8_t patch[] = {0x20, 0x00, 0x80, 0xD2}; // mov x0, #1
#elif defined(__x86_64__)
uint8_t patch[] = {0xB8, 0x01, 0x00, 0x00, 0x00}; // mov eax, 1
#endif
write_mem((void *)targetAddr, patch, sizeof(patch));
```

## Best Practices

- Minimize changes to a single app or helper hook file per task.
- Validate class, symbol, and address availability before hooking.
- Ensure C function, IMP, and block completion signatures match the original ABI exactly.
- Prefer symbol lookup or signature scan over hardcoded offsets; limit version scope with `getSupportAppVersion`.
- Log key images, addresses, control flow branches, and return values with `NSLogger` for runtime diagnosis.
