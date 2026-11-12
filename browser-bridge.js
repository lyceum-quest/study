/*
 * The only maintained JavaScript in Lyceum Study.
 *
 * This file initializes Elm (or the roc-signals module #app names) and
 * translates generic storage messages into IndexedDB requests. Fetching,
 * parsing, validation, normalization, and all application decisions belong in
 * Elm or Roc.
 */
(function () {
  "use strict";

  const databaseName = "aristos";
  const databaseVersion = 1;

  function openDatabase() {
    return new Promise(function (resolve, reject) {
      const request = indexedDB.open(databaseName, databaseVersion);

      request.onupgradeneeded = function () {
        const database = request.result;
        if (!database.objectStoreNames.contains("corpora")) {
          database.createObjectStore("corpora", { keyPath: "id" });
        }
        if (!database.objectStoreNames.contains("metadata")) {
          database.createObjectStore("metadata", { keyPath: "key" });
        }
        if (!database.objectStoreNames.contains("progress")) {
          database.createObjectStore("progress", { keyPath: "id" });
        }
      };
      request.onsuccess = function () { resolve(request.result); };
      request.onerror = function () { reject(request.error); };
    });
  }

  function requestResult(request) {
    return new Promise(function (resolve, reject) {
      request.onsuccess = function () { resolve(request.result); };
      request.onerror = function () { reject(request.error); };
    });
  }

  function transactionResult(transaction) {
    return new Promise(function (resolve, reject) {
      transaction.oncomplete = function () { resolve(); };
      transaction.onerror = function () { reject(transaction.error); };
      transaction.onabort = function () { reject(transaction.error); };
    });
  }

  async function performStorage(message) {
    const database = await openDatabase();

    try {
      if (message.operation === "get") {
        const transaction = database.transaction(message.store, "readonly");
        return (await requestResult(transaction.objectStore(message.store).get(message.key))) || null;
      }

      if (message.operation === "put") {
        const transaction = database.transaction(message.store, "readwrite");
        transaction.objectStore(message.store).put(message.value);
        await transactionResult(transaction);
        return message.value;
      }

      if (message.operation === "getAll") {
        const transaction = database.transaction(message.store, "readonly");
        return await requestResult(transaction.objectStore(message.store).getAll());
      }

      if (message.operation === "clear") {
        const transaction = database.transaction(message.store, "readwrite");
        transaction.objectStore(message.store).clear();
        await transactionResult(transaction);
        return null;
      }

      throw new Error("Unsupported storage operation");
    } finally {
      database.close();
    }
  }

  function answer(message, respond) {
    performStorage(message).then(function (value) {
      respond({ id: message.id, ok: true, value: value });
    }).catch(function (error) {
      console.warn("Lyceum Study storage request failed", error);
      respond({ id: message.id, ok: false, value: null });
    });
  }

  // The roc-signals app's port: a batch of messages per data-request, each
  // answer (plus "now") as the value of a change event. See signals/Store.roc.
  customElements.define("lyceum-store", class extends HTMLElement {
    static observedAttributes = ["data-request"];

    attributeChangedCallback(name, previous, batch) {
      if (!batch) return;
      JSON.parse(batch).forEach((message) => answer(message, (response) => {
        response.now = Date.now();
        this.value = JSON.stringify(response);
        this.dispatchEvent(new Event("change", { bubbles: true }));
      }));
    }
  });

  const node = document.getElementById("app");

  if (node.dataset.wasm) {
    import(node.dataset.runtime).then((runtime) => runtime.mountRocEngineApp({ wasmUrl: node.dataset.wasm, root: node, onFault: console.error })).catch(console.error);
    return;
  }

  const app = Elm.Main.init({ node: node, flags: null });

  app.ports.storageRequest.subscribe(function (message) {
    answer(message, app.ports.storageResponse.send);
  });
})();
