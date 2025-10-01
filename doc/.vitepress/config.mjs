import { joinURL, withoutTrailingSlash } from "ufo";
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

const siteUrl = "https://codecompanion.olimorris.dev";

const baseHeaders = [
  ["meta", { name: "twitter:site", content: "@olimorris_" }],
  ["meta", { name: "twitter:card", content: "summary_large_image" }],
  [
    "meta",
    {
      name: "twitter:image:src",
      content: siteUrl + "/assets/images/social_banner.png",
    },
  ],
  [
    "meta",
    {
      property: "og:image",
      content: siteUrl + "/assets/images/social_banner.png",
    },
  ],
  [
    "meta",
    {
      name: "twitter:image",
      content: siteUrl + "/assets/images/social_banner.png",
    },
  ],
  ["meta", { property: "og:image:width", content: "1280" }],
  ["meta", { property: "og:image:height", content: "640" }],
  ["meta", { property: "og:image:type", content: "image/png" }],
  [
    "meta",
    { property: "og:site_name", content: "CodeCompanion.nvim Documentation" },
  ],
  ["meta", { property: "og:type", content: "website" }],
  [
    "link",
    {
      rel: "sitemap",
      type: "application/xml",
      title: "Sitemap",
      href: siteUrl + "/sitemap.xml",
    },
  ],
];

const umamiScript = [
  "script",
  {
    defer: "true",
    src: "https://cloud.umami.is/script.js",
    "data-website-id": "6fb6c149-1aba-4531-b613-7fc54d42191a",
  },
];
const headers = inProd ? [...baseHeaders, umamiScript] : baseHeaders;

// https://vitepress.dev/reference/site-config
export default withMermaid(
  defineConfig({
    mermaid: {
      securityLevel: "loose", // Allows more flexibility
      theme: "base", // Use base theme to allow CSS variables to take effect
    },
    // optionally set additional config for plugin itself with MermaidPluginConfig
    title: "CodeCompanion.nvim Documentation",
    description:
      "AI coding in Neovim, leveraging LLMs from OpenAI and Anthropic. Support for agents and tools.",
    lang: "en",
    cleanUrls: true,
    head: headers,
    sitemap: { hostname: siteUrl },
    themeConfig: {
      logo: "https://github.com/user-attachments/assets/7083eeb1-2f6c-4cf6-82ff-bc3171cab801",
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
            { text: "Action Palette", link: "/configuration/action-palette" },
            { text: "Adapters", link: "/configuration/adapters" },
            { text: "Chat Buffer", link: "/configuration/chat-buffer" },
            { text: "Extensions", link: "/configuration/extensions" },
            {
              text: "Inline Assistant",
              link: "/configuration/inline-assistant",
            },
            { text: "Memory", link: "/configuration/memory" },
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
              link: "/usage/chat-buffer/",
              collapsed: true,
              items: [
                { text: "Agents", link: "/usage/chat-buffer/agents" },
                { text: "Memory", link: "/usage/chat-buffer/memory" },
                {
                  text: "Slash Commands",
                  link: "/usage/chat-buffer/slash-commands",
                },
                { text: "Tools", link: "/usage/chat-buffer/tools" },
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
            { text: "Creating Extensions", link: "/extending/extensions" },
            { text: "Creating Memory Parsers", link: "/extending/parsers" },
            { text: "Creating Prompts", link: "/extending/prompts" },
            { text: "Creating Tools", link: "/extending/tools" },
            { text: "Creating Workflows", link: "/extending/workflows" },
            { text: "Creating Workspaces", link: "/extending/workspace" },
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
    transformPageData: (page, { siteConfig }) => {
      page.frontmatter = page.frontmatter || {};

      // Initialize the `head` frontmatter if it doesn't exist.
      page.frontmatter.head ??= [];

      const title =
        (page.frontmatter.title || page.title) + " | " + siteConfig.site.title;
      const description =
        page.frontmatter.description ||
        page.description ||
        siteConfig.site.description;
      const url = joinURL(
        siteUrl,
        withoutTrailingSlash(page.filePath.replace(/(index)?\.md$/, "")),
      );

      page.frontmatter.head.push(
        [
          "meta",
          {
            property: "og:title",
            content: title,
          },
        ],
        [
          "meta",
          {
            name: "twitter:title",
            content: title,
          },
        ],
        [
          "meta",
          {
            property: "og:description",
            content: description,
          },
        ],
        [
          "meta",
          {
            name: "twitter:description",
            content: description,
          },
        ],
        [
          "link",
          {
            rel: "canonical",
            href: url,
          },
        ],
        [
          "meta",
          {
            property: "og:url",
            content: url,
          },
        ],
      );
    },
  }),
);
