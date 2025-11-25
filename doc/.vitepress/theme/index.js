import DefaultTheme from "vitepress/theme";
import "./vaporwave.css";
import { enhanceAppWithTabs } from "vitepress-plugin-tabs/client";

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    enhanceAppWithTabs(app);
  },
};
