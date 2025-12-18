# For WinOS under Powershell use this script instead of make
# Ensure you have file, pandoc and stylua installed
# scoop install file pandoc stylua

function Install-Deps
{
    if (!(Test-Path "deps"))
    { New-Item -ItemType Directory -Path "deps" 
    }
    
    $deps = @{
        "plenary.nvim"    = "https://github.com/nvim-lua/plenary.nvim.git"
        "nvim-treesitter" = "https://github.com/nvim-treesitter/nvim-treesitter.git"
        "mini.nvim"       = "https://github.com/echasnovski/mini.nvim"
        "panvimdoc"       = "https://github.com/kdheepak/panvimdoc"
    }

    foreach ($name in $deps.Keys)
    {
        $path = "deps/$name"
        if (!(Test-Path $path))
        {
            Write-Host "Pulling $name..." -ForegroundColor Cyan
            git clone --filter=blob:none $($deps[$name]) $path
        }
    }
}

function Invoke-Format
{
    Write-Host "Formatting..." -ForegroundColor Cyan
    stylua tests/ lua/ -f ./stylua.toml
}

function Invoke-Docs
{
    Install-Deps
    Write-Host "Generating Docs..." -ForegroundColor Cyan
    pandoc `
        --metadata="project:codecompanion" `
        --metadata="vimversion:NVIM v0.11" `
        --metadata="titledatepattern:%Y %B %d" `
        --metadata="toc:true" `
        --metadata="incrementheadinglevelby:0" `
        --metadata="treesitter:true" `
        --metadata="dedupsubheadings:true" `
        --metadata="ignorerawblocks:true" `
        --metadata="docmapping:false" `
        --metadata="docmappingproject:true" `
        --lua-filter deps/panvimdoc/scripts/include-files.lua `
        --lua-filter deps/panvimdoc/scripts/skip-blocks.lua `
        --lua-filter scripts/panvimdoc-cleanup.lua `
        -t deps/panvimdoc/scripts/panvimdoc.lua `
        scripts/vimdoc.md `
        -o doc/codecompanion.txt
}

function Invoke-Test
{
    param($File)

    Install-Deps
    $env:HOME = $env:USERPROFILE  
    Write-Host "Testing..." -ForegroundColor Cyan
    if ($File)
    {
        nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$File')"
    } else
    {
        nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"
    }
}

if ($args[0] -eq "format")
{ Invoke-Format 
} elseif ($args[0] -eq "docs")
{ Invoke-Docs
} elseif ($args[0] -eq "test")
{ Invoke-Test 
} elseif ($args[0] -eq "test_file")
{ Invoke-Test -File $args[1] 
} else
{ 
    Invoke-Format
    Invoke-Docs
    Invoke-Test 
}
