import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";
import { apiInitializer } from "discourse/lib/api";
import { defaultHomepage } from "discourse/lib/utilities";
import I18n from "I18n";

// Global Set to store topic IDs already rendered
const renderedTopicIds = new Set();

export default apiInitializer("1.14.0", (api) => {
  const filteredTopicsLists = settings.presets;

  filteredTopicsLists.forEach((LIST) => {
    const listTitle = LIST.title.trim();
    const listLength = LIST.length;
    const listQuery = LIST.query.trim();
    const listPluginOutlet = LIST.plugin_outlet.trim();
    const listShowOn = LIST.show_on;
    const listSelectedCategories = LIST.selected_categories;
    const listSelectedTags = LIST.selected_tags;

    api.renderInOutlet(
      listPluginOutlet,
      class FilteredList extends Component {
        @service store;
        @service router;
        @service siteSettings;
        @tracked filteredTopics = [];
        @tracked isLoading = true;

        constructor() {
          super(...arguments);
          this.findFilteredTopics();
        }

        @action
        async findFilteredTopics() {
          try {
            this.isLoading = true;

            const topicList = await this.store.findFiltered("topicList", {
              filter: "filter",
              params: { q: listQuery },
            });

            if (topicList.topics) {
              const uniqueTopics = topicList.topics.filter(
                (t) => !renderedTopicIds.has(t.id)
              );

              uniqueTopics.slice(0, listLength).forEach((t) =>
                renderedTopicIds.add(t.id)
              );

              this.filteredTopics = uniqueTopics.slice(0, listLength);
            }
          } finally {
            this.isLoading = false;
          }
        }

        get showOnRoute() {
          const currentRoute = this.router.currentRoute;

          switch (listShowOn) {
            case "everywhere":
              return !currentRoute.name.includes("admin");

            case "homepage":
              return currentRoute.name === `discovery.${defaultHomepage()}`;

            case "top_menu":
              const topMenu = this.siteSettings.top_menu;
              const targets = topMenu
                .split("|")
                .map((opt) => `discovery.${opt}`);
              return targets.includes(currentRoute.name);

            case "categories":
              return currentRoute.name === "discovery.categories";

            case "latest":
              return currentRoute.name === "discovery.latest";

            case "top":
              return currentRoute.name === "discovery.top";

            case "new":
              return currentRoute.name === "discovery.new";

            case "unread":
              return currentRoute.name === "discovery.unread";

            case "read":
              return currentRoute.name === "discovery.read";

            case "posted":
              return currentRoute.name === "discovery.posted";

            case "bookmarks":
              return currentRoute.name === "discovery.bookmarks";

            case "hot":
              return currentRoute.name === "discovery.hot";

            case "selected_categories":
              const categoryId = currentRoute.attributes?.category?.id;
              return (
                currentRoute.name === "discovery.category" &&
                listSelectedCategories.includes(categoryId)
              );

            case "selected_tags":
              const tagId = currentRoute.attributes?.tag?.id;
              return (
                currentRoute.name === "tag.show" &&
                listSelectedTags.includes(tagId)
              );

            default:
              return false;
          }
        }
      }
    );
  });
});
