package simslim

import (
	"os"
	"testing"
)

// Tests assert exact English progress lines, so pin the language instead of
// inheriting the machine locale (which is Chinese on many developer Macs).
func TestMain(m *testing.M) {
	SetLanguage("en")
	os.Exit(m.Run())
}

func TestLocalizedFormatting(t *testing.T) {
	SetLanguage("zh-Hans")
	defer SetLanguage("en")

	if got := TR("Booted %s.\n", "ABC"); got != "已启动 ABC。\n" {
		t.Errorf("TR() = %q, want the Chinese line", got)
	}
	if got := TRValue("Widgets & Wallpaper"); got != "小组件与壁纸" {
		t.Errorf("TRValue() = %q, want the Chinese category name", got)
	}
	if got := TR("not in the table %d", 3); got != "not in the table 3" {
		t.Errorf("untranslated key = %q, want the English fallback", got)
	}
}

func TestEnglishIsByteIdentical(t *testing.T) {
	if got := TR("Booted %s.\n", "ABC"); got != "Booted ABC.\n" {
		t.Errorf("TR() = %q, want the original English line", got)
	}
	if got := TRValue("Widgets & Wallpaper"); got != "Widgets & Wallpaper" {
		t.Errorf("TRValue() = %q, want the original English value", got)
	}
}
