user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("mail.dark-reader.enabled", true);
user_pref("layout.css.prefers-color-scheme.content-override", 1);

/* Conversations の tweakFonts() が body:has(> .moz-text-html) へ
 * browser.display.{foreground,background}_color の値を焼き込む。
 * 未設定だと既定の #FFFFFF が入り、詳細度 (0,1,1) で userContent.css の
 * body 指定 (0,0,1) に勝つため本文が白くなる。値の側を Mocha に合わせる。 */
user_pref("browser.display.background_color", "#1e1e2e");
user_pref("browser.display.foreground_color", "#cdd6f4");
