import { defineConfig } from "vitepress";
import { execSync } from "node:child_process";

const version = "Main";
if (process.env.IS_RELEASE === "true") {
  const version = execSync("git describe --tags --abbrev=0", {
    encoding: "utf-8",
  }).trim();
}
const isMain = process.env.IS_RELEASE !== "true";

const siteUrl = "https://codecompanion.olimorris.dev";

const title = isMain ? "Main" : version;
const otherTitle = isMain ? version : "Main";

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: "CodeCompanion.nvim",
  description: "AI-powered coding, seamlessly in Neovim",
  sitemap: { hostname: siteUrl },
  themeConfig: {
    nav: [
      {
        text: `${title}`,
        items: [
          {
            text: "Changelog",
            link: "https://github.com/olimorris/codecompanion.nvim/blob/main/CHANGELOG.md",
          },
          {
            text: "Contributing",
            link: "https://github.com/olimorris/codecompanion.nvim/blob/main/.github/contributing.md",
          },
        ],
      },
    ],

    sidebar: [
      { text: "Introduction", link: "/" },
      { text: "Installation", link: "installation" },
      { text: "Getting Started", link: "getting-started" },
      {
        text: "Configuration",
        collapsed: true,
        items: [
          { text: "Introduction", link: "/configuration/introduction" },
          { text: "Action Palette", link: "/configuration/action-palette" },
          { text: "Adapters", link: "/configuration/adapters" },
          { text: "Chat Buffer", link: "/configuration/chat-buffer" },
          { text: "Inline Assistant", link: "/configuration/inline-assistant" },
          { text: "Prompt Library", link: "/configuration/prompt-library" },
          { text: "System Prompt", link: "/configuration/system-prompt" },
          { text: "Others", link: "/configuration/others" },
        ],
      },
      {
        text: "Usage",
        collapsed: false,
        items: [
          { text: "Introduction", link: "/usage/introduction" },
          { text: "Action Palette", link: "/usage/action-palette" },
          {
            text: "Chat Buffer",
            link: "/usage/chat-buffer",
            collapsed: true,
            items: [
              { text: "Agents/Tools", link: "/usage/chat-buffer/agents" },
              {
                text: "Slash Commands",
                link: "/usage/chat-buffer/slash-commands",
              },
              { text: "Variables", link: "/usage/chat-buffer/variables" },
            ],
          },
          { text: "Events", link: "/usage/events" },
          { text: "Inline Assistant", link: "/usage/inline-assistant" },
          { text: "Workflows", link: "/usage/workflows" },
          { text: "Others", link: "/usage/others" },
        ],
      },
      {
        text: "Extending the Plugin",
        collapsed: true,
        items: [
          { text: "Creating Adapters", link: "/extending/adapters" },
          { text: "Creating Prompts", link: "/extending/prompts" },
          { text: "Creating Tools", link: "/extending/tools" },
        ],
      },
    ],

    editLink: {
      pattern:
        "https://github.com/olimorris/codecompanion.nvim/edit/main/doc/:path",
      text: "Edit this page on GitHub",
    },

    footer: {
      message: "Released under the MIT License.",
      copyright: "Copyright © 2024-present Oli Morris",
    },

    socialLinks: [
      {
        icon: "github",
        link: "https://github.com/olimorris/codecompanion.nvim",
      },
    ],

    search: { provider: "local" },
  },
});
