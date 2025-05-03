import { defineConfig } from "vitepress";
import { execSync } from "node:child_process";
import { withMermaid } from "vitepress-plugin-mermaid";
import fs from "node:fs";
import path from "node:path";

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

const extensionsDir = path.resolve(__dirname, "../extensions");

// Return a list of extensions
function getExtensionSidebarItems() {
  try {
    const files = fs.readdirSync(extensionsDir);
    return files
      .filter((file) => file.endsWith(".md") && file !== "index.md")
      .map((file) => {
        const nameWithoutExt = path.basename(file, ".md");
        const filePath = path.join(extensionsDir, file);
        let text = "";

        try {
          const content = fs.readFileSync(filePath, "utf-8");
          const lines = content.split("\n");
          const h1Line = lines.find((line) => line.startsWith("# "));
          if (h1Line) {
            text = h1Line.substring(2).trim(); // Extract text after '# '
          }
        } catch (readError) {
          console.error(`Error reading file ${filePath}:`, readError);
        }

        // Fallback if H1 not found or file read error
        if (!text) {
          text = nameWithoutExt
            .split("-")
            .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
            .join(" ");
        }

        return {
          text: text,
          link: `/extensions/${nameWithoutExt}`,
        };
      });
  } catch (error) {
    console.error("Error reading extensions directory:", error);
    return [];
  }
}

const extensionItems = getExtensionSidebarItems();

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
        {
          text: "Community Extensions",
          collapsed: true,
          items: extensionItems,
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
  }),
);
