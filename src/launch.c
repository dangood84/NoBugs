/*
 * The parade is Pascal. The door is C.
 *
 * Free Pascal's own main does not hang an NSAutoreleasePool, and the
 * Objective-C runtime on this Mac will complain, leak, or abort the
 * first time AppKit autoreleases something into an empty corridor.
 * A constructor runs before PASCALMAIN, which is early enough: unit
 * initialization has not touched Cocoa yet.
 *
 * The other half of the same crash is numeric. Cocoa is comfortable
 * with denormal floats; the Pascal runtime turns them into fatal
 * exceptions. Mask the trap bits here, and again once Pascal is up,
 * because the RTL may reset the FPCR during its own startup.
 *
 * Lemmings, the old desktop ones, already knew this. They walk off the
 * edge of whatever ground you give them. The ground here is a window
 * ledge. The launch has to be standing there before they arrive.
 */

#include <objc/runtime.h>
#include <objc/message.h>

static id gPool;

__attribute__((constructor))
static void nobugs_cocoa_launch(void)
{
    unsigned long long fpcr;
    Class poolClass;
    SEL allocSel;
    SEL initSel;

    __asm__ volatile("mrs %0, fpcr" : "=r"(fpcr));
    /* IDE/IXE/UFE/OFE/DZE/IOE — the trap enables. Clear them. */
    fpcr &= ~((unsigned long long)0x9F00);
    __asm__ volatile("msr fpcr, %0" :: "r"(fpcr));

    poolClass = objc_getClass("NSAutoreleasePool");
    if (poolClass == 0)
        return;
    allocSel = sel_registerName("alloc");
    initSel = sel_registerName("init");
    gPool = ((id (*)(id, SEL))objc_msgSend)((id)poolClass, allocSel);
    gPool = ((id (*)(id, SEL))objc_msgSend)(gPool, initSel);
}
