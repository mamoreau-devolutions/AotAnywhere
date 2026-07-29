/* GS-cookie page pad, compiled into every macOS Native AOT link.

   Some Mach-O linker configurations keep __DATA,__const inside the __DATA segment (ld64
   migrates it to __DATA_CONST), and .NET's InitGSCookie() startup code
   write-protects the whole 16 KiB page holding the GS cookie, which lives
   in __const. Without padding, the start of __data shares that page and the
   runtime crashes with SIGBUS on its next startup write. The alignment below
   forces __data onto its own page.

   Shipping this as a static source lets the MSBuild-level link
   (DirectLink.targets) reference it directly. */
__attribute__((used, section("__DATA,__data"), aligned(16384)))
static volatile char aotanywhere_data_page_pad = 1;
