/* Vigil site — bilingual switching for a single static page. */
(function () {
  "use strict";

  var STORAGE_KEY = "vigil.lang";

  var META = {
    zh: {
      htmlLang: "zh-CN",
      title: "警惕 Vigil · 保护你自己电脑上的重要文件",
      description:
        "警惕 / Vigil 把你在用的目录加入保护清单：只在本机工作，不上传文件内容，出现受保护的操作、保护中断或疑似换人时拦截、记录或提醒。"
    },
    en: {
      htmlLang: "en",
      title: "Vigil · Protect the important files on your own Mac",
      description:
        "Vigil adds the folders you already use to a protection list. It works only on your Mac, never uploads file contents, and intercepts, records, or alerts when a protected action happens."
    }
  };

  function readQueryLang() {
    var match = /[?&]lang=(zh|en)\b/.exec(window.location.search);
    return match ? match[1] : null;
  }

  function readStoredLang() {
    try {
      var value = window.localStorage.getItem(STORAGE_KEY);
      return value === "zh" || value === "en" ? value : null;
    } catch (error) {
      return null;
    }
  }

  function detectLang() {
    return readQueryLang() || readStoredLang() || ((navigator.language || "").toLowerCase().indexOf("zh") === 0 ? "zh" : "en");
  }

  function persist(lang) {
    try {
      window.localStorage.setItem(STORAGE_KEY, lang);
    } catch (error) {
      /* storage may be unavailable in private modes; the page still works */
    }
  }

  function setMeta(selector, value) {
    var node = document.querySelector(selector);
    if (node) node.setAttribute("content", value);
  }

  function applyLang(lang, options) {
    var settings = META[lang] || META.zh;
    var root = document.documentElement;

    root.setAttribute("data-lang", lang);
    root.setAttribute("lang", settings.htmlLang);
    document.title = settings.title;

    setMeta('meta[name="description"]', settings.description);
    setMeta('meta[property="og:title"]', settings.title);
    setMeta('meta[property="og:description"]', settings.description);

    var buttons = document.querySelectorAll("[data-set-lang]");
    for (var i = 0; i < buttons.length; i += 1) {
      var active = buttons[i].getAttribute("data-set-lang") === lang;
      buttons[i].setAttribute("aria-pressed", active ? "true" : "false");
    }

    if (options && options.persist) persist(lang);
    if (options && options.syncUrl) {
      try {
        var url = new URL(window.location.href);
        url.searchParams.set("lang", lang);
        window.history.replaceState(null, "", url.toString());
      } catch (error) {
        /* older browsers: skip the URL sync */
      }
    }
  }

  document.addEventListener("click", function (event) {
    var trigger = event.target.closest ? event.target.closest("[data-set-lang]") : null;
    if (!trigger) return;
    event.preventDefault();
    var lang = trigger.getAttribute("data-set-lang");
    if (lang === "zh" || lang === "en") applyLang(lang, { persist: true, syncUrl: true });
  });

  applyLang(detectLang());
})();
