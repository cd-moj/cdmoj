document.addEventListener("DOMContentLoaded", function () {
  const content = document.querySelector(".treinoList");
  const itemsPerPage = 2;
  let currentPage = 0;
  const items = Array.from(content.getElementsByTagName("li")).slice(0);

  // paginated requests done wrong 101
  function updateTable(page) {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", "treino.sh/" + page);
    xhr.onreadystatechange = function () {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status === 200) {
          console.log(xhr.responseText);
        } else {
          alert("Erro ao carregar conteúdo do treinamento.");
        }
      }
    };
    xhr.send();
  }

  function showPage(page) {
    const startIndex = page * itemsPerPage;
    const endIndex = startIndex + itemsPerPage;
    items.forEach((item, index) => {
      item.classList.toggle("hidden", index < startIndex || index >= endIndex);
    });
    updateActiveButtonStates();
    updateButtons();
  }

  function createPageButtons() {
    const totalPages = Math.ceil(items.length / itemsPerPage);
    const paginationContainer = document.createElement("div");
    paginationContainer.classList.add("pagination");

    function createButtons(s, f) {
      for (let i = s; i < f; i++) {
        const pageButton = document.createElement("button");
        pageButton.classList.add("page");
        pageButton.textContent = i;
        pageButton.addEventListener("click", () => {
          currentPage = i - 1;
          showPage(currentPage);
        });
        paginationContainer.appendChild(pageButton);
      }
    }

    function createFirst() {
      const separator = document.createElement("i");
      separator.textContent = "...";

      const pageButton = document.createElement("button");
      pageButton.classList.add("page");
      pageButton.textContent = 1;
      pageButton.addEventListener("click", () => {
        currentPage = 0;
        showPage(currentPage);
      });
      paginationContainer.appendChild(pageButton);
      paginationContainer.appendChild(separator);
    }

    function createLast() {
      const separator = document.createElement("i");
      separator.textContent = "...";
      const pageButton = document.createElement("button");
      pageButton.classList.add("page");
      pageButton.textContent = totalPages;
      pageButton.addEventListener("click", () => {
        currentPage = totalPages - 1;
        showPage(currentPage);
      });
      paginationContainer.appendChild(separator);
      paginationContainer.appendChild(pageButton);
    }

    const previousButton = document.createElement("button");
    previousButton.classList.add("previousbutton");
    previousButton.textContent = "◄";
    previousButton.addEventListener("click", () => {
      if (currentPage > 0) {
        currentPage--;
        showPage(currentPage);
      }
    });
    paginationContainer.appendChild(previousButton);

    const surround = 3;

    if (totalPages < 10) {
      createButtons(1, totalPages + 1);
    } else if (currentPage < surround * 3 - 2) {
      createButtons(1, surround * 3 - 1);
      createLast();
    } else if (currentPage > totalPages - surround * 2 - 1) {
      createFirst();
      createButtons(totalPages - surround * 2 + 1, totalPages + 1);
    } else {
      createFirst();
      createButtons(currentPage - 1, currentPage + 4);
      createLast();
    }

    const nextButton = document.createElement("button");
    nextButton.classList.add("nextbutton");
    nextButton.textContent = "►";
    nextButton.addEventListener("click", () => {
      if (currentPage < totalPages - 1) {
        currentPage++;
        showPage(currentPage);
      }
    });
    paginationContainer.appendChild(nextButton);

    const tabs = document.querySelector(".treinoTabs");

    tabs.insertBefore(paginationContainer, tabs.firstChild);

    updateActiveButtonStates();
  }

  function updateButtons() {
    const pagination = document.querySelectorAll(".pagination");
    pagination[0].remove();
    createPageButtons();
  }

  function updateActiveButtonStates() {
    const pageButtons = document.querySelectorAll(".pagination button.page");
    pageButtons.forEach((button, index) => {
      if (Number(button.innerText) - 1 === currentPage) {
        button.classList.add("active");
      } else {
        button.classList.remove("active");
      }
    });
  }

  if (items.length > 0) {
    createPageButtons();
    showPage(currentPage);
  }
});
