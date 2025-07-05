import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";
// ConditionalLoadingSpinner is removed
import TopicList from "discourse/components/topic-list";
import { apiInitializer } from "discourse/lib/api";
import { defaultHomepage } from "discourse/lib/utilities";

// --- Caching and Global State ---
// A simple in-memory cache for topic list data based on the query.
// Stores promises, so concurrent requests for the same query don't re-fetch.
const topicListCache = new Map();

// Global set to keep track of topic IDs that have already been displayed across all lists
const displayedTopicIds = new Set();
// --- End Caching and Global State ---

export default apiInitializer("1.14.0", (api) => {
  const filtered_topics_lists = settings.presets;

  // --- Define the individual FilteredList component (now presentation-only and no spinner) ---
  class FilteredList extends Component {
    @service router;
    @service siteSettings;

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
            {{! The TopicList component will render with whatever topics it receives }}
            {{! If @filteredTopics is null or empty initially, it will render an empty list }}
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

  // --- Define the main container component that fetches all data ---
  api.renderInOutlet(
    // !!! IMPORTANT: Verify this plugin outlet is active on the pages
    // where you expect your lists to appear.
    // Common choices: "above-topic-list-bottom", "topic-list-before",
    // "above-main-content", or a custom one from your theme.
    "above-topic-list-bottom",
    class AllFilteredListsContainer extends Component {
      @service store;
      @tracked allListsData = {}; // Stores fetched topics keyed by list title

      constructor() {
        super(...arguments);
        // Clear displayedTopicIds on initialization of the container
        // to ensure fresh unique lists on page load/re-render.
        displayedTopicIds.clear();
        this.fetchAllFilteredTopics();
      }

      @action
      async fetchAllFilteredTopics() {
        const fetchPromises = filtered_topics_lists.map(async (LIST) => {
          const listQuery = LIST.query.trim();

          // 1. Check cache first
          if (topicListCache.has(listQuery)) {
            // Return the promise from the cache if it exists (for de-duplication of fetches)
            return topicListCache.get(listQuery).then(cachedResult => ({
                listTitle: LIST.title.trim(),
                topics: cachedResult.topics,
                length: LIST.length,
            }));
          }

          // 2. If not in cache, create a new fetch promise
          const fetchPromise = this.store.findFiltered("topicList", {
            filter: "filter",
            params: {
              q: listQuery,
            },
          }).then(topicList => ({
              listTitle: LIST.title.trim(),
              topics: topicList.topics,
              length: LIST.length,
          }));

          // Store the promise in the cache
          topicListCache.set(listQuery, fetchPromise);
          return fetchPromise;
        });

        const results = await Promise.all(fetchPromises);
        const consolidatedData = {};

        results.forEach((result) => {
          const uniqueTopics = [];
          for (const topic of result.topics || []) {
            if (!displayedTopicIds.has(topic.id)) {
              uniqueTopics.push(topic);
              displayedTopicIds.add(topic.id);
            }
            if (uniqueTopics.length >= result.length) {
              break;
            }
          }
          consolidatedData[result.listTitle] = uniqueTopics;
        });

        this.allListsData = consolidatedData;
      }

      <template>
        {{! No ConditionalLoadingSpinner here }}
        {{#each filtered_topics_lists as |LIST|}}
          <FilteredList
            @listTitle={{LIST.title.trim}}
            @listLength={{LIST.length}}
            @listQuery={{LIST.query.trim}}
            @listPluginOutlet={{LIST.plugin_outlet.trim}}
            @listShowOn={{LIST.show_on}}
            @listSelectedCategories={{LIST.selected_categories}}
            @listSelectedTags={{LIST.selected_tags}}
            {{! Pass the fetched data (might be empty initially) }}
            @filteredTopics={{this.allListsData.[LIST.title.trim]}}
          />
        {{/each}}
      </template>
    }
  );
});
