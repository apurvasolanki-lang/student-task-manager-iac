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
  account_id  = var.cloudflare_account_id
  script_name = "student-task-manager"

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

    if (path === "/") {
      return new Response("Student Task Manager API is running!", {
        headers: {
          ...corsHeaders,
          "Content-Type": "text/plain"
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