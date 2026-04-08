import { defineClientComponent, useData } from "vitepress";
import { computed, defineComponent } from "vue";

const ClientCopyOrDownloadAsMarkdownButtons = defineClientComponent(() => {
  return import("vitepress-plugin-llms/vitepress-components/CopyOrDownloadAsMarkdownButtons.vue");
});

export default defineComponent({
  name: "CopyOrDownloadAsMarkdownButtons",
  setup() {
    const { page } = useData();

    const shouldShow = computed(() => {
      // Hide component if path starts with /zh
      return !page.value.relativePath.startsWith("zh");
    });

    return () => {
      if (!shouldShow.value) return null;

      return <ClientCopyOrDownloadAsMarkdownButtons />;
    };
  },
});
