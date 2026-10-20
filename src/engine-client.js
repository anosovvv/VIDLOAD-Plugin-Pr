const EngineClient = (() => {
  const baseURL = "http://127.0.0.1:17383/v1";

  async function request(path, options) {
    const response = await fetch(`${baseURL}${path}`, {
      headers: { "Content-Type": "application/json" },
      ...options
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(body || `VIDLOAD Engine responded with ${response.status}.`);
    }

    return response.json();
  }

  async function health() {
    return request("/health");
  }

  async function createDownload({ url, format }) {
    return request("/downloads", {
      method: "POST",
      body: JSON.stringify({ url, format, consumer: "premiere" })
    });
  }

  async function getDownload(id) {
    return request(`/downloads/${encodeURIComponent(id)}`);
  }

  async function cancelDownload(id) {
    return request(`/downloads/${encodeURIComponent(id)}`, { method: "DELETE" });
  }

  return { health, createDownload, getDownload, cancelDownload };
})();
