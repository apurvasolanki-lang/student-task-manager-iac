
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

resource "cloudflare_workers_kv_namespace" "task_storage" {
  account_id = var.cloudflare_account_id
  title      = "student-task-storage"
}

resource "cloudflare_workers_script" "task_manager" {
  account_id         = var.cloudflare_account_id
  script_name        = "student-task-manager"
  compatibility_date = "2026-11-01"

  bindings = [{
    name         = "TASK_STORAGE"
    namespace_id = cloudflare_workers_kv_namespace.task_storage.id
    type         = "kv_namespace"
  }]

  content = <<-EOT
addEventListener("fetch", event => {
  event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  };

  const jsonResponse = (data, status = 200) =>
    new Response(JSON.stringify(data), {
      status,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json"
      }
    });

  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders
    });
  }

  const url = new URL(request.url);
  const path = url.pathname;
  const storageKey = "tasks";

  try {
    const tasks = await TASK_STORAGE.get(storageKey, "json") || [];

    if (path === "/tasks" && request.method === "GET") {
      return jsonResponse(tasks);
    }

    if (path === "/tasks" && request.method === "POST") {
      const body = await request.json();
      const title = String(body.title || "").trim();

      if (!title) {
        return jsonResponse({ error: "Task title required" }, 400);
      }

      const task = {
        id: crypto.randomUUID(),
        title,
        completed: false
      };

      tasks.push(task);
      await TASK_STORAGE.put(storageKey, JSON.stringify(tasks));

      return jsonResponse(task, 201);
    }

    const match = path.match(new RegExp("^/tasks/([^/]+)$"));

    if (match && request.method === "PUT") {
      const id = decodeURIComponent(match[1]);
      const body = await request.json();
      const task = tasks.find(item => item.id === id);

      if (!task) {
        return jsonResponse({ error: "Task not found" }, 404);
      }

      task.completed = Boolean(body.completed);
      await TASK_STORAGE.put(storageKey, JSON.stringify(tasks));

      return jsonResponse(task);
    }

    if (match && request.method === "DELETE") {
      const id = decodeURIComponent(match[1]);
      const updatedTasks = tasks.filter(item => item.id !== id);

      if (updatedTasks.length === tasks.length) {
        return jsonResponse({ error: "Task not found" }, 404);
      }

      await TASK_STORAGE.put(storageKey, JSON.stringify(updatedTasks));
      return jsonResponse({ success: true });
    }

    if (path === "/" || path === "/index.html") {
      const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Student Task Manager</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: Arial, sans-serif;
      background: linear-gradient(135deg, #e0e7ff, #f5f3ff);
      min-height: 100vh;
      padding: 40px 16px;
      color: #1f2937;
    }
    .container {
      max-width: 650px;
      margin: 0 auto;
      background: #ffffff;
      padding: 32px;
      border-radius: 18px;
      box-shadow: 0 12px 35px rgba(31, 41, 55, 0.12);
    }
    header { text-align: center; margin-bottom: 28px; }
    header h1 { color: #4338ca; font-size: 30px; margin-bottom: 10px; }
    header p { color: #6b7280; }
    #task-form { display: flex; gap: 10px; margin-bottom: 22px; }
    #task-input {
      flex: 1; min-width: 0; padding: 13px;
      border: 1px solid #d1d5db; border-radius: 8px; font-size: 15px;
    }
    button {
      border: none; border-radius: 8px; padding: 12px 17px;
      background: #4f46e5; color: white; font-weight: bold; cursor: pointer;
    }
    button:hover { background: #3730a3; }
    .task-summary {
      display: flex; justify-content: space-between; gap: 10px;
      margin-bottom: 18px; padding: 13px; background: #eef2ff;
      border-radius: 8px; font-size: 14px; font-weight: bold;
    }
    #task-list { list-style: none; }
    .task-item {
      display: flex; align-items: center; gap: 10px;
      padding: 14px 0; border-bottom: 1px solid #e5e7eb;
    }
    .task-text { flex: 1; overflow-wrap: anywhere; }
    .task-item.completed .task-text { text-decoration: line-through; color: #9ca3af; }
    .task-item button { padding: 8px 10px; font-size: 12px; }
    .task-item .delete-btn { background: #dc2626; }
    #message { margin-top: 15px; color: #4338ca; text-align: center; }
    @media (max-width: 480px) {
      .container { padding: 22px 16px; }
      header h1 { font-size: 25px; }
      #task-form { flex-direction: column; }
      .task-summary { flex-direction: column; }
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>Student Task Manager</h1>
      <p>Organize your tasks. Stay productive.</p>
    </header>
    <form id="task-form">
      <input id="task-input" type="text" placeholder="Enter a new task..." required>
      <button type="submit">Add Task</button>
    </form>
    <div class="task-summary">
      <span id="total-tasks">Total: 0</span>
      <span id="completed-tasks">Completed: 0</span>
    </div>
    <ul id="task-list"></ul>
    <p id="message" role="status"></p>
  </div>
  <script>
    const API_URL = "";
    const taskForm = document.getElementById("task-form");
    const taskInput = document.getElementById("task-input");
    const taskList = document.getElementById("task-list");
    const totalTasks = document.getElementById("total-tasks");
    const completedTasks = document.getElementById("completed-tasks");
    const message = document.getElementById("message");
    let tasks = [];

    function showMessage(text) { message.textContent = text; }

    function updateSummary() {
      totalTasks.textContent = "Total: " + tasks.length;
      completedTasks.textContent = "Completed: " + tasks.filter(t => t.completed).length;
    }

    function renderTasks() {
      taskList.replaceChildren();
      tasks.forEach(task => {
        const item = document.createElement("li");
        item.className = "task-item";
        if (task.completed) item.classList.add("completed");

        const checkbox = document.createElement("input");
        checkbox.type = "checkbox";
        checkbox.checked = task.completed;
        checkbox.setAttribute("aria-label", "Complete " + task.title);
        checkbox.addEventListener("change", async () => {
          try {
            const res = await fetch("/tasks/" + task.id, {
              method: "PUT",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ completed: checkbox.checked })
            });
            if (!res.ok) throw new Error("Update failed");
            task.completed = checkbox.checked;
            renderTasks();
            showMessage("Task updated!");
          } catch {
            checkbox.checked = task.completed;
            showMessage("Task update failed. Please try again.");
          }
        });

        const title = document.createElement("span");
        title.className = "task-text";
        title.textContent = task.title;

        const deleteButton = document.createElement("button");
        deleteButton.className = "delete-btn";
        deleteButton.textContent = "Delete";
        deleteButton.addEventListener("click", async () => {
          try {
            const res = await fetch("/tasks/" + task.id, { method: "DELETE" });
            if (!res.ok) throw new Error("Delete failed");
            tasks = tasks.filter(t => t.id !== task.id);
            renderTasks();
            showMessage("Task deleted.");
          } catch {
            showMessage("Delete failed. Please try again.");
          }
        });

        item.append(checkbox, title, deleteButton);
        taskList.appendChild(item);
      });
      updateSummary();
    }

    async function loadTasks() {
      try {
        const res = await fetch("/tasks");
        if (!res.ok) throw new Error("Loading failed");
        tasks = await res.json();
        renderTasks();
        showMessage("Tasks loaded successfully!");
      } catch {
        showMessage("Could not connect to API. Please try again.");
      }
    }

    taskForm.addEventListener("submit", async event => {
      event.preventDefault();
      const title = taskInput.value.trim();
      if (!title) return;
      try {
        const res = await fetch("/tasks", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ title })
        });
        if (!res.ok) throw new Error("Add failed");
        taskInput.value = "";
        await loadTasks();
        showMessage("Task added successfully!");
      } catch {
        showMessage("Could not add task. Please try again.");
      }
    });

    loadTasks();
  </script>
</body>
</html>`;
      return new Response(html, {
        headers: {
          ...corsHeaders,
          "Content-Type": "text/html; charset=utf-8"
        }
      });
    }

    return jsonResponse({ error: "Route not found" }, 404);
  } catch (error) {
    return jsonResponse({ error: "Internal server error" }, 500);
  }
}
EOT
}
