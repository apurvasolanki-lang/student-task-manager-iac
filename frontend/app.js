const API_URL = "https://student-task-manager.apurvasolanki301.workers.dev";

const taskForm = document.getElementById("task-form");
const taskInput = document.getElementById("task-input");
const taskList = document.getElementById("task-list");
const totalTasks = document.getElementById("total-tasks");
const completedTasks = document.getElementById("completed-tasks");
const message = document.getElementById("message");

let tasks = [];

function showMessage(text) {
  message.textContent = text;
}

function updateSummary() {
  totalTasks.textContent = `Total: ${tasks.length}`;
  completedTasks.textContent =
    `Completed: ${tasks.filter(task => task.completed).length}`;
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
    checkbox.setAttribute("aria-label", `Complete ${task.title}`);

    checkbox.addEventListener("change", async () => {
      try {
        const response = await fetch(`${API_URL}/tasks/${task.id}`, {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ completed: checkbox.checked })
        });

        if (!response.ok) throw new Error("Update failed");

        task.completed = checkbox.checked;
        renderTasks();
        showMessage("Task updated!");
      } catch {
        checkbox.checked = task.completed;
        showMessage("Task update nahi hua. API check karo.");
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
        const response = await fetch(`${API_URL}/tasks/${task.id}`, {
          method: "DELETE"
        });

        if (!response.ok) throw new Error("Delete failed");

        tasks = tasks.filter(current => current.id !== task.id);
        renderTasks();
        showMessage("Task deleted.");
      } catch {
        showMessage("Task delete nahi hua. API check karo.");
      }
    });

    item.append(checkbox, title, deleteButton);
    taskList.appendChild(item);
  });

  updateSummary();
}

async function loadTasks() {
  try {
    const response = await fetch(`${API_URL}/tasks`);
    if (!response.ok) throw new Error("Loading failed");

    tasks = await response.json();
    renderTasks();
    showMessage("Tasks loaded successfully!");
  } catch {
    showMessage("API abhi connect nahi hai. Pehle Worker API update karenge.");
  }
}

taskForm.addEventListener("submit", async event => {
  event.preventDefault();

  const title = taskInput.value.trim();
  if (!title) return;

  try {
    const response = await fetch(`${API_URL}/tasks`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title })
    });

    if (!response.ok) throw new Error("Add failed");

    taskInput.value = "";
    await loadTasks();
    showMessage("Task added successfully!");
  } catch {
    showMessage("Task add nahi hua. Worker API update karna baaki hai.");
  }
});

loadTasks();