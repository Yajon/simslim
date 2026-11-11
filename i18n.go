package simslim

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strings"
	"sync"
)

// CLI language resolution order:
//   1. SIMSLIM_LANG (the GUI passes the language its UI was actually built with)
//   2. appLanguage saved by the GUI (for a terminal CLI started outside the app)
//   3. LC_ALL / LANG
//   4. the macOS global AppleLanguages preference
//   5. English
//
// Machine-readable output (--json) and Go error values are never localized, so
// the GUI, scripts and tests keep seeing the same data regardless of language.

const (
	langEnglish = "en"
	langChinese = "zh-Hans"
	guiBundleID = "app.mobai.simslim"
)

var (
	languageOnce     sync.Once
	activeLanguage   string
	appleLanguagesRe = regexp.MustCompile(`"([^"]+)"`)
)

// CurrentLanguage returns "en" or "zh-Hans".
func CurrentLanguage() string {
	languageOnce.Do(func() { activeLanguage = detectLanguage() })
	return activeLanguage
}

// SetLanguage overrides the detected language. It is used by tests and by
// callers that already know which language to render.
func SetLanguage(language string) {
	languageOnce.Do(func() {})
	activeLanguage = normalizeLanguage(language)
	if activeLanguage == "" {
		activeLanguage = langEnglish
	}
}

// TR translates a printf-style format string and formats it. Untranslated keys
// fall back to the original English text, so English output stays byte-for-byte
// identical to the pre-localization CLI.
func TR(format string, arguments ...any) string {
	text := format
	if CurrentLanguage() == langChinese {
		if translated, ok := chineseStrings[format]; ok {
			text = translated
		}
	}
	if len(arguments) == 0 {
		return text
	}
	return fmt.Sprintf(text, arguments...)
}

// TRValue translates a plain data string (category name, description, ...).
func TRValue(value string) string {
	if CurrentLanguage() == langChinese {
		if translated, ok := chineseStrings[value]; ok {
			return translated
		}
	}
	return value
}

func detectLanguage() string {
	for _, candidate := range []string{
		os.Getenv("SIMSLIM_LANG"),
		guiLanguage(),
		os.Getenv("LC_ALL"),
		os.Getenv("LANG"),
		globalAppleLanguages(),
	} {
		if language := normalizeLanguage(candidate); language != "" {
			return language
		}
	}
	return langEnglish
}

func normalizeLanguage(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	lower := strings.ToLower(value)
	switch {
	case strings.HasPrefix(lower, "en"):
		return langEnglish
	case strings.HasPrefix(lower, "zh"):
		// Only Simplified Chinese has a translation table; Traditional Chinese
		// falls back to English rather than showing the wrong script.
		if strings.Contains(lower, "hant") || strings.Contains(lower, "tw") || strings.Contains(lower, "hk") {
			return langEnglish
		}
		return langChinese
	default:
		return ""
	}
}

func guiLanguage() string {
	if runtime.GOOS != "darwin" {
		return ""
	}
	out, err := exec.Command("defaults", "read", guiBundleID, "appLanguage").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func globalAppleLanguages() string {
	if runtime.GOOS != "darwin" {
		return ""
	}
	out, err := exec.Command("defaults", "read", "-g", "AppleLanguages").Output()
	if err != nil {
		return ""
	}
	if match := appleLanguagesRe.FindStringSubmatch(string(out)); len(match) > 1 {
		return match[1]
	}
	return ""
}
