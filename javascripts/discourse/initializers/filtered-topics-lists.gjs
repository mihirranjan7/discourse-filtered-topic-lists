import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";
import ConditionalLoadingSpinner from "discourse/components/conditional-loading-spinner";
import TopicList from "discourse/components/topic-list";
import { apiInitializer } from "discourse/lib/api";
import { defaultHomepage } from "discourse/lib/utilities";

export default apiInitializer("1.14.0", (api) => {
  const filtered_topics_lists = settings.presets;

  // Shared set for deduplication across all FilteredList instances
  const seenTopicIds = new Set();

  filtered_topics_lists.forEach((LIST, idx) => {
    const list_length = LIST.length;
    const list_query = LIST.query.trim();
    const list_plugin_outlet = LIST.plugin_outlet.trim();
    const list_show_on = LIST.show_on;
    const list_selected_categories = LIST.selected_categories;
    const list_selected_tags = LIST.selected_tags;

    api.renderInOutlet(
      list_plugin_outlet,
      class FilteredList extends Component {
        @service store;
        @service router;
        @service siteSettings;
        @tracked filteredTopics = [];
        @tracked isLoading = false;

        constructor() {
          super(...arguments);
          if (idx === 0) seenTopicIds.clear();
          this.findFilteredTopics();
        }

        @action
        async findFilteredTopics() {
          this.isLoading = true;
          const topicList = await this.store.findFiltered("topicList", {
            filter: "filter",
            params: { q: list_query },
          });

          if (topicList.topics) {
            const deduped = [];
            for (let topic of topicList.topics) {
              if (!seenTopicIds.has(topic.id)) {
                deduped.push(topic);
                seenTopicIds.add(topic.id);
              }
              if (deduped.length >= list_length) break;
            }
            this.filteredTopics = deduped;
          } else {
            this.filteredTopics = [];
          }
          this.isLoading = false;
        }

        get showOnRoute() {
          const currentRoute = this.router.currentRoute;
          switch (list_show_on) {
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
              const category_id = currentRoute.attributes?.category?.id;
              return (
                currentRoute.name === "discovery.category" &&
                list_selected_categories.includes(category_id)
              );
            case "selected_tags":
              const tag_id = currentRoute.attributes?.tag?.id;
              return (
                currentRoute.name === "tag.show" &&
                list_selected_tags.includes(tag_id)
              );
            default:
              return false;
          }
        }

        static template = /* hbs */ `
          {{#if this.showOnRoute}}
            <div class="filtered-topics-list ${list_plugin_outlet}">
              <div class="filtered-topics-list__wrapper">
                <ConditionalLoadingSpinner @condition={{this.isLoading}}>
                  <TopicList
                    @topics={{this.filteredTopics}}
                    @showPosters="true"
                    class="filtered-topics-list__content"
                  />
                </ConditionalLoadingSpinner>
              </div>
            </div>
          {{/if}}
        `;
      }
    );
  });
});
