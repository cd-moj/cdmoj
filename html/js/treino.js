document.addEventListener("DOMContentLoaded", function () {
  class Pagination {
    constructor(content) {
      this.content = content;
      this.itemsPerPage = 8;
      this.currentPage = 0;
      this.items = Array.from(this.content.getElementsByTagName("li")).slice(0);
      this.createPageButtons();
      this.showPage(this.currentPage);
    }

    showPage(page) {
      const startIndex = page * this.itemsPerPage;
      const endIndex = startIndex + this.itemsPerPage;
      this.items.forEach((item, index) => {
        item.classList.toggle("hidden", index < startIndex || index >= endIndex);
      });
      this.updateActiveButtonStates();
      this.updateButtons()
    }

    createPageButtons() {
      const totalPages = Math.ceil(this.items.length / this.itemsPerPage);
      this.paginationContainer = document.createElement("div");
      this.paginationContainer.classList.add("pagination");

      const createButtons = (s, f) => {
        for (let i = s; i < f; i++) {
          const pageButton = document.createElement("button");
          pageButton.classList.add("page");
          pageButton.textContent = i;
          pageButton.addEventListener("click", () => {
            this.currentPage = i - 1;
            this.showPage(this.currentPage);
          });
          this.paginationContainer.appendChild(pageButton);
        }
      };

      const createFirst = () => {
        const separator = document.createElement("i");
        separator.textContent = "...";

        const pageButton = document.createElement("button");
        pageButton.classList.add("page");
        pageButton.textContent = 1;
        pageButton.addEventListener("click", () => {
          this.currentPage = 0;
          this.showPage(this.currentPage);
        });
        this.paginationContainer.appendChild(pageButton);
        this.paginationContainer.appendChild(separator);
      };

      const createLast = () => {
        const separator = document.createElement("i");
        separator.textContent = "...";
        const pageButton = document.createElement("button");
        pageButton.classList.add("page");
        pageButton.textContent = totalPages;
        pageButton.addEventListener("click", () => {
          this.currentPage = totalPages - 1;
          this.showPage(this.currentPage);
        });
        this.paginationContainer.appendChild(separator);
        this.paginationContainer.appendChild(pageButton);
      };

      const previousButton = document.createElement("button");
      previousButton.classList.add("previousbutton");
      previousButton.textContent = "◄";
      previousButton.addEventListener("click", () => {
        if (this.currentPage > 0) {
          this.currentPage--;
          this.showPage(this.currentPage);
        }
      });
      this.paginationContainer.appendChild(previousButton);

      const surround = 3;

      if (totalPages < 10) {
        createButtons(1, totalPages + 1);
      } else if (this.currentPage < surround * 3 - 2) {
        createButtons(1, surround * 3 - 1);
        createLast();
      } else if (this.currentPage > totalPages - surround * 2 - 1) {
        createFirst();
        createButtons(totalPages - surround * 2 + 1, totalPages + 1);
      } else {
        createFirst();
        createButtons(this.currentPage - 1, this.currentPage + 4);
        createLast();
      }

      const nextButton = document.createElement("button");
      nextButton.classList.add("nextbutton");
      nextButton.textContent = "►";
      nextButton.addEventListener("click", () => {
        if (this.currentPage < totalPages - 1) {
          this.currentPage++;
          this.showPage(this.currentPage);
        }
      });
      this.paginationContainer.appendChild(nextButton);
      
      
		if (!document.querySelector(".conquistas")) {
		  const conqButton = document.createElement("button");
		  conqButton.classList.add("conqButton");
		  conqButton.textContent = "Conquistas";
		  conqButton.addEventListener("click", function () {
		    window.location.href = "/cgi-bin/conquistas.sh";
		  });
		  this.paginationContainer.appendChild(conqButton);
		}

      const tabs = this.content.closest('.treinoTabs');
      
      tabs.insertBefore(this.paginationContainer, tabs.firstChild);

      this.updateActiveButtonStates();
    }

    updateButtons() {
      const pagination = this.content.closest('.treinoTabs').querySelector(".pagination");
      pagination.remove();
      this.createPageButtons();
    }
    
    updateActiveButtonStates() {
      const pageButtons = this.paginationContainer.querySelectorAll(".pagination button.page");
      console.log(pageButtons);
      pageButtons.forEach((button, index) => {
        console.log(button.innerText, "<b = i>", index, " cp>", this.currentPage);
        if (Number(button.innerText) - 1 === this.currentPage) {
          button.classList.add("active");
        } else {
          button.classList.remove("active");
        }
      });
    }
  }

  const treinoLists = document.querySelectorAll(".treinoList");
  treinoLists.forEach(content => new Pagination(content));
});
