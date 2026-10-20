/* global require, navigator, PremiereBridge, EngineClient */

const { entrypoints } = require("uxp");

const translations = {
  en: {
    subtitle: "Download and add media to your project",
    linkLabel: "Link",
    linkHint: "Use links to media you are allowed to save.",
    formatLabel: "Format",
    video: "Video",
    audio: "Audio",
    destinationLabel: "Import to",
    destinationLoading: "Current project",
    downloadAndImport: "Download & Import",
    stagePreparing: "Preparing",
    stageDownloading: "Downloading",
    stageConverting: "Preparing media",
    stageImporting: "Adding to project",
    engineChecking: "Checking VIDLOAD Engine…",
    engine: "VIDLOAD Engine",
    checking: "Checking…",
    engineReady: "Ready",
    engineAvailable: "VIDLOAD Engine is ready.",
    engineUnavailable: "Not running",
    engineMissing: "VIDLOAD Engine is not running. Start it, then try again.",
    linkRequired: "Paste a valid link first.",
    projectUnavailable: "Open a Premiere Pro project before importing media.",
    preparing: "Preparing download",
    downloading: "Downloading media",
    converting: "Preparing for Premiere",
    importing: "Adding to project",
    complete: "Added to project",
    addedTo: "Added to",
    failed: "Download failed"
  },
  ru: {
    subtitle: "Скачивайте и добавляйте медиа в проект",
    linkLabel: "Ссылка",
    linkHint: "Используйте ссылки на материалы, которые имеете право сохранять.",
    formatLabel: "Формат",
    video: "Видео",
    audio: "Аудио",
    destinationLabel: "Добавить в",
    destinationLoading: "Текущий проект",
    downloadAndImport: "Скачать и добавить",
    stagePreparing: "Подготовка",
    stageDownloading: "Скачивание",
    stageConverting: "Подготовка медиа",
    stageImporting: "Добавление в проект",
    engineChecking: "Проверяем VIDLOAD Engine…",
    engine: "VIDLOAD Engine",
    checking: "Проверяем…",
    engineReady: "Готов",
    engineAvailable: "VIDLOAD Engine готов к работе.",
    engineUnavailable: "Не запущен",
    engineMissing: "VIDLOAD Engine не запущен. Запустите его и повторите попытку.",
    linkRequired: "Сначала вставьте корректную ссылку.",
    projectUnavailable: "Перед импортом откройте проект Premiere Pro.",
    preparing: "Подготавливаем загрузку",
    downloading: "Скачиваем медиа",
    converting: "Подготавливаем для Premiere",
    importing: "Добавляем в проект",
    complete: "Добавлено в проект",
    addedTo: "Добавлено в",
    failed: "Загрузка не выполнена"
  }
};

const state = {
  language: "ru",
  format: "mp4",
  engineReady: false,
  activeDownloadID: null,
  pollingTimer: null
};

const $ = (selector) => document.querySelector(selector);
const t = (key) => translations[state.language][key] || key;

function setNotice(kind, message) {
  const notice = $("#notice");
  if (kind === "hidden") {
    notice.className = "notice is-hidden";
    return;
  }
  notice.className = `notice notice-${kind}`;
  $("#notice-text").textContent = message;
  $(".notice-icon").textContent = kind === "success" ? "✓" : kind === "error" ? "!" : "i";
}

function setStage(stage, progress, detail) {
  $("#progress-card").classList.remove("is-hidden");
  $("#engine-footer").classList.add("is-hidden");
  $("#progress-title").textContent = t(stage);
  $("#progress-detail").textContent = detail || "";
  $("#progress-percentage").textContent = Number.isFinite(progress) ? `${Math.round(progress)}%` : "";
  $("#progress-bar").style.width = `${Math.max(0, Math.min(progress || 0, 100))}%`;

  document.querySelectorAll(".stage-list li").forEach((item) => {
    const itemStage = item.dataset.stage;
    const orderedStages = ["preparing", "downloading", "converting", "importing"];
    const itemIndex = orderedStages.indexOf(itemStage);
    const activeIndex = orderedStages.indexOf(stage);
    item.classList.toggle("is-active", itemIndex === activeIndex);
    item.classList.toggle("is-complete", itemIndex < activeIndex || stage === "complete");
  });
}

function setBusy(isBusy) {
  $("#download-button").classList.toggle("is-disabled", isBusy);
  $("#download-button").setAttribute("aria-disabled", String(isBusy));
  $("#video-url").disabled = isBusy;
  document.querySelectorAll(".format-option").forEach((option) => {
    option.classList.toggle("is-disabled", isBusy);
    option.setAttribute("aria-disabled", String(isBusy));
  });
}

function applyTranslations() {
  document.documentElement.lang = state.language;
  document.querySelectorAll("[data-i18n]").forEach((element) => {
    element.textContent = t(element.dataset.i18n);
  });
  $("#language-button").textContent = state.language === "en" ? "RU" : "EN";
}

async function updateDestination() {
  try {
    $("#destination-name").textContent = await PremiereBridge.getDestinationName();
  } catch (_) {
    $("#destination-name").textContent = t("destinationLoading");
  }
}

async function checkEngine() {
  $("#engine-status-text").textContent = t("checking");
  try {
    await EngineClient.health();
    state.engineReady = true;
    $("#engine-status").classList.add("is-ready");
    $("#engine-status-text").textContent = t("engineReady");
    setNotice("hidden");
  } catch (_) {
    state.engineReady = false;
    $("#engine-status").classList.remove("is-ready");
    $("#engine-status-text").textContent = t("engineUnavailable");
    setNotice("warning", t("engineMissing"));
  }
}

function updateFromEngine(job) {
  const stage = job.stage || "preparing";
  const progress = typeof job.progress === "number" ? job.progress : 0;
  const detail = job.detail || "";
  setStage(stage, progress, detail);
}

async function finishDownload(job) {
  clearInterval(state.pollingTimer);
  state.pollingTimer = null;
  setStage("importing", 100, "");

  try {
    const destination = await PremiereBridge.importFile(job.outputPath);
    setStage("complete", 100, "");
    setNotice("success", `${t("complete")}: ${t("addedTo")} ${destination.binName}.`);
  } catch (error) {
    setNotice("error", error.message || t("projectUnavailable"));
  } finally {
    state.activeDownloadID = null;
    setBusy(false);
    updateDestination();
  }
}

async function pollDownload() {
  if (!state.activeDownloadID) return;

  try {
    const job = await EngineClient.getDownload(state.activeDownloadID);
    updateFromEngine(job);

    if (job.status === "completed") {
      await finishDownload(job);
    } else if (job.status === "failed" || job.status === "cancelled") {
      clearInterval(state.pollingTimer);
      state.pollingTimer = null;
      state.activeDownloadID = null;
      setBusy(false);
      setNotice("error", job.error || t("failed"));
    }
  } catch (error) {
    clearInterval(state.pollingTimer);
    state.pollingTimer = null;
    state.activeDownloadID = null;
    setBusy(false);
    setNotice("error", error.message || t("failed"));
  }
}

async function startDownload() {
  const url = $("#video-url").value.trim();
  if (!/^https?:\/\//i.test(url)) {
    setNotice("warning", t("linkRequired"));
    return;
  }

  if (!state.engineReady) {
    await checkEngine();
    if (!state.engineReady) return;
  }

  try {
    await PremiereBridge.getDestinationName();
  } catch (_) {
    setNotice("error", t("projectUnavailable"));
    return;
  }

  setBusy(true);
  setStage("preparing", 0, "");
  setNotice("info", t("preparing"));

  try {
    const job = await EngineClient.createDownload({ url, format: state.format });
    state.activeDownloadID = job.id;
    await pollDownload();
    if (state.activeDownloadID) {
      state.pollingTimer = setInterval(pollDownload, 800);
    }
  } catch (error) {
    setBusy(false);
    setNotice("error", error.message || t("failed"));
  }
}

function bindActivate(element, handler) {
  element.addEventListener("click", () => {
    if (element.getAttribute("aria-disabled") !== "true") handler();
  });
  element.addEventListener("keydown", (event) => {
    if ((event.key === "Enter" || event.key === " ") && element.getAttribute("aria-disabled") !== "true") {
      event.preventDefault();
      handler();
    }
  });
}

function initializeUI() {
  bindActivate($("#download-button"), startDownload);
  bindActivate($("#language-button"), () => {
    state.language = state.language === "en" ? "ru" : "en";
    applyTranslations();
    updateDestination();
    checkEngine();
  });
  document.querySelectorAll(".format-option").forEach((option) => {
    bindActivate(option, () => {
      state.format = option.dataset.format;
      document.querySelectorAll(".format-option").forEach((candidate) => {
        const selected = candidate === option;
        candidate.classList.toggle("is-selected", selected);
        candidate.setAttribute("aria-checked", String(selected));
      });
    });
  });
  applyTranslations();
  updateDestination();
  checkEngine();
}

entrypoints.setup({
  panels: {
    "vidload-panel": {
      create() {
        initializeUI();
      },
      show() {
        updateDestination();
        checkEngine();
      }
    }
  }
});
