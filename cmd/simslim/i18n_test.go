package main

import (
	"os"
	"strings"
	"testing"

	"github.com/mobai-app/simslim"
)

// CLI tests assert the exact English output, so pin the language instead of
// inheriting the machine locale (which is Chinese on many developer Macs).
func TestMain(m *testing.M) {
	simslim.SetLanguage("en")
	os.Exit(m.Run())
}

func TestEnglishOutputUnchanged(t *testing.T) {
	cases := []struct{ got, want string }{
		{tr("Booted %s.\n", "ABC"), "Booted ABC.\n"},
		{tr("Cancelled; no profile written."), "Cancelled; no profile written."},
		{trValue("Widgets & Wallpaper"), "Widgets & Wallpaper"},
		{trValue("partially slim"), "partially slim"},
	}
	for _, tt := range cases {
		if tt.got != tt.want {
			t.Errorf("got %q, want %q", tt.got, tt.want)
		}
	}
}

func TestChineseOutput(t *testing.T) {
	simslim.SetLanguage("zh-Hans")
	defer simslim.SetLanguage("en")

	cases := []struct{ got, want string }{
		{tr("Booted %s.\n", "ABC"), "已启动 ABC。\n"},
		{tr("Cancelled; no profile written."), "已取消，未写入配置。"},
		{trValue("Widgets & Wallpaper"), "小组件与壁纸"},
		{trValue("partially slim"), "部分瘦身"},
	}
	for _, tt := range cases {
		if tt.got != tt.want {
			t.Errorf("got %q, want %q", tt.got, tt.want)
		}
	}
	if got := simslim.CurrentLanguage(); got != "zh-Hans" {
		t.Errorf("CurrentLanguage() = %q, want zh-Hans", got)
	}
}

func TestUsageTexts(t *testing.T) {
	if !strings.Contains(usageEnglish, "USAGE") || !strings.Contains(usageEnglish, "simslim <command>") {
		t.Error("English help text lost its usage section")
	}
	if !strings.Contains(usageChinese, "用法") || !strings.Contains(usageChinese, "simslim <命令>") {
		t.Error("Chinese help text lost its usage section")
	}
}

func TestStaticFleetChinese(t *testing.T) {
	simslim.SetLanguage("zh-Hans")
	defer simslim.SetLanguage("en")

	mem := &simslim.Measurement{Processes: 70, Bytes: 900 * 1 << 20, CPU: 12}
	out := simslim.TopOutput{
		Sims:       []simslim.TopSim{{Device: simslim.Device{UDID: "ABCD1234-5678", Name: "iPhone 15"}, Memory: mem}},
		TotalBytes: 900 * 1 << 20,
	}
	got := staticFleet(out)
	// Device names and the fixed-width column labels stay untouched.
	for _, want := range []string{"台已启动", "iPhone 15", "SIMULATOR"} {
		if !strings.Contains(got, want) {
			t.Errorf("staticFleet output missing %q\n%s", want, got)
		}
	}
}
