import { defineConfig } from "vitepress";
import { execSync } from "node:child_process";
import { withMermaid } from "vitepress-plugin-mermaid";

const inProd = process.env.NODE_ENV === "production";

let version = "Main";
if (inProd) {
  try {
    version = execSync("git describe --tags --abbrev=0", {
      encoding: "utf-8",
    }).trim();
  } catch (error) {
    console.warn("Failed to get git version, using default.");
  }
}

const baseHeaders = [];
const umamiScript = [
  "script",
  {
    defer: "true",
    src: "https://cloud.umami.is/script.js",
    "data-website-id": "6fb6c149-1aba-4531-b613-7fc54d42191a",
  },
];
const headers = inProd ? [baseHeaders, umamiScript] : baseHeaders;

const siteUrl = "https://codecompanion.olimorris.dev";


// https://vitepress.dev/reference/site-config
export default withMermaid(
  defineConfig({
    mermaid: {
      securityLevel: "loose", // Allows more flexibility
      theme: "base", // Use base theme to allow CSS variables to take effect
    },
    // optionally set additional config for plugin itself with MermaidPluginConfig
    title: "CodeCompanion",
    description: "AI-powered coding, seamlessly in Neovim",
    head: headers,
    sitemap: { hostname: siteUrl },
    themeConfig: {
      logo: "https://github.com/user-attachments/assets/825fc040-9bc8-4743-be2a-71e257f8a7be",
      nav: [
        {
          text: `${version}`,
          items: [
            {
              text: "Changelog",
              link: "https://github.com/olimorris/codecompanion.nvim/blob/main/CHANGELOG.md",
            },
            {
              text: "Contributing",
              link: "https://github.com/olimorris/codecompanion.nvim/blob/main/CONTRIBUTING.md",
            },
          ],
        },
      ],

      sidebar: [
        { text: "Introduction", link: "/" },
        { text: "Installation", link: "/installation" },
        { text: "Getting Started", link: "/getting-started" },
        {
          text: "Configuration",
          collapsed: true,
          items: [
            { text: "Introduction", link: "/configuration/introduction" },
            { text: "Action Palette", link: "/configuration/action-palette" },
            { text: "Adapters", link: "/configuration/adapters" },
            { text: "Chat Buffer", link: "/configuration/chat-buffer" },
            {
              text: "Inline Assistant",
              link: "/configuration/inline-assistant",
            },
            { text: "Prompt Library", link: "/configuration/prompt-library" },
            { text: "System Prompt", link: "/configuration/system-prompt" },
            { text: "Extensions", link: "/configuration/extensions" },
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
              link: "/usage/chat-buffer/",
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
            { text: "User Interface", link: "/usage/ui" },
            { text: "Workflows", link: "/usage/workflows" },
          ],
        },
        {
          text: "Extending the Plugin",
          collapsed: true,
          items: [
            { text: "Creating Adapters", link: "/extending/adapters" },
            { text: "Creating Prompts", link: "/extending/prompts" },
            { text: "Creating Tools", link: "/extending/tools" },
            { text: "Creating Workflows", link: "/extending/workflows" },
            { text: "Creating Workspaces", link: "/extending/workspace" },
            { text: "Creating Extensions", link: "/extending/extensions" },
          ],
        },
        { text: "Community Extensions", link: "/extensions" },
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
  }),
);
