import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";
import ConditionalLoadingSpinner from "discourse/components/conditional-loading-spinner";
import TopicList from "discourse/components/topic-list";
import { apiInitializer } from "discourse/lib/api";
import { defaultHomepage } from "discourse/lib/utilities";

// Global set to keep track of topic IDs that have already been displayed
const displayedTopicIds = new Set();

export default apiInitializer("1.14.0", (api) => {
  const filtered_topics_lists = settings.presets;

  // Define the individual FilteredList component (now presentation-only)
  class FilteredList extends Component {
    @service router;
    @service siteSettings;

    // These are now received as arguments from the parent component
    // @arguments: @listTitle, @listLength, @listQuery, @listPluginOutlet, @listShowOn, @listSelectedCategories, @listSelectedTags, @filteredTopics

    get showOnRoute() {
      const currentRoute = this.router.currentRoute;
      const list_show_on = this.args.listShowOn;
      const list_selected_categories = this.args.listSelectedCategories;
      const list_selected_tags = this.args.listSelectedTags;

      switch (list_show_on) {
        case "everywhere":
          return !currentRoute.name.includes("admin");

        case "homepage":
          return currentRoute.name === `discovery.${defaultHomepage()}`;

        case "top_menu":
          const topMenu = this.siteSettings.top_menu;
          const targets = topMenu.split("|").map((opt) => `discovery.${opt}`);
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

    <template>
      {{#if this.showOnRoute}}
        <div class="filtered-topics-list {{this.args.listPluginOutlet}}">
          <div class="filtered-topics-list__wrapper">
            {{#if this.args.listTitle}}
              <div class="filtered-topics-list__header">
                <h2>{{this.args.listTitle}}</h2>
              </div>
            {{/if}}
            {{! ConditionalLoadingSpinner is now handled by the parent component }}
            <TopicList
              @topics={{this.args.filteredTopics}}
              @showPosters="true"
              class="filtered-topics-list__content"
            />
          </div>
        </div>
      {{/if}}
    </template>
  }

  // Define the main container component that fetches all data
  api.renderInOutlet(
    // Choose an appropriate plugin outlet where you want these lists to appear.
    // 'above-topic-list-bottom' or 'topic-list-before' are common.
    // Ensure this outlet exists in your Discourse theme/plugin.
    "above-topic-list-bottom",
    class AllFilteredListsContainer extends Component {
      @service store;
      @tracked allListsData = {}; // Stores fetched topics keyed by list title
      @tracked isLoadingAllLists = false;

      constructor() {
        super(...arguments);
        // Clear displayedTopicIds on initialization of the container
        // to ensure fresh lists on page load/re-render.
        displayedTopicIds.clear();
        this.fetchAllFilteredTopics();
      }

      @action
      async fetchAllFilteredTopics() {
        this.isLoadingAllLists = true;
        try {
          const fetchPromises = filtered_topics_lists.map(async (LIST) => {
            const topicList = await this.store.findFiltered("topicList", {
              filter: "filter",
              params: {
                q: LIST.query.trim(),
              },
            });
            return {
              listTitle: LIST.title.trim(),
              topics: topicList.topics,
              length: LIST.length, // Pass the desired length
            };
          });

          const results = await Promise.all(fetchPromises);
          const consolidatedData = {};

          results.forEach((result) => {
            const uniqueTopics = [];
            for (const topic of result.topics || []) { // Ensure topicList.topics is not null/undefined
              // If the topic hasn't been displayed yet
              if (!displayedTopicIds.has(topic.id)) {
                uniqueTopics.push(topic);
                displayedTopicIds.add(topic.id); // Add it to our global tracker
              }
              // Stop once we've collected enough unique topics for this list
              if (uniqueTopics.length >= result.length) {
                break;
              }
            }
            consolidatedData[result.listTitle] = uniqueTopics;
          });

          this.allListsData = consolidatedData;
        } finally {
          this.isLoadingAllLists = false; // Always set loading to false when done
        }
      }

      <template>
        <ConditionalLoadingSpinner @condition={{this.isLoadingAllLists}}>
          {{#each filtered_topics_lists as |LIST|}}
            <FilteredList
              @listTitle={{LIST.title.trim}}
              @listLength={{LIST.length}}
              @listQuery={{LIST.query.trim}}
              @listPluginOutlet={{LIST.plugin_outlet.trim}}
              @listShowOn={{LIST.show_on}}
              @listSelectedCategories={{LIST.selected_categories}}
              @listSelectedTags={{LIST.selected_tags}}
              @filteredTopics={{this.allListsData.[LIST.title.trim]}}
            />
          {{/each}}
        </ConditionalLoadingSpinner>
      </template>
    }
  );
});
