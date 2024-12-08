defmodule ExDoc.Formatter.Markdown do
  @moduledoc false

  @mimetype "text/markdown"
  @assets_dir "MD/assets"
  alias __MODULE__.{Assets, Templates}
  alias ExDoc.Formatter.HTML
  alias ExDoc.Utils

  @doc """
  Generates Markdown documentation for the given modules.
  """
  @spec run([ExDoc.ModuleNode.t()], [ExDoc.ModuleNode.t()], ExDoc.Config.t()) :: String.t()
  def run(project_nodes, filtered_modules, config) when is_map(config) do
    Utils.unset_warned()

    config = normalize_config(config)
    File.rm_rf!(config.output)
    File.mkdir_p!(Path.join(config.output, "MD"))

    project_nodes =
      HTML.render_all(project_nodes, filtered_modules, ".md", config, highlight_tag: "samp")

    nodes_map = %{
      modules: HTML.filter_list(:module, project_nodes),
      tasks: HTML.filter_list(:task, project_nodes)
    }

    extras =
      config
      |> HTML.build_extras(".xhtml")
      |> Enum.chunk_by(& &1.group)
      |> Enum.map(&{hd(&1).group, &1})

    config = %{config | extras: extras}

    static_files = HTML.generate_assets("MD", default_assets(config), config)
    HTML.generate_logo(@assets_dir, config)
    HTML.generate_cover(@assets_dir, config)

    # generate_nav(config, nodes_map)
    generate_extras(config)
    generate_list(config, nodes_map.modules)
    generate_list(config, nodes_map.tasks)

    {:ok, epub} = generate_zip(config.output)
    File.rm_rf!(config.output)
    Path.relative_to_cwd(epub)
  end

  defp normalize_config(config) do
    output =
      config.output
      |> Path.expand()
      |> Path.join("#{config.project}")

    %{config | output: output}
  end

  defp generate_extras(config) do
    for {_title, extras} <- config.extras do
      Enum.each(extras, fn %{id: id, title: title, title_content: _title_content, source: content} ->
        output = "#{config.output}/MD/#{id}.md"
        content = """
        # #{title}

        #{content}
        """

        if File.regular?(output) do
          Utils.warn("file #{Path.relative_to_cwd(output)} already exists", [])
        end

        File.write!(output, content)
      end)
    end
  end




  defp generate_list(config, nodes) do
    nodes
    |> Task.async_stream(&generate_module_page(&1, config), timeout: :infinity)
    |> Enum.map(&elem(&1, 1))
  end

  defp generate_zip(output) do
    :zip.create(
      String.to_charlist("#{output}-markdown.zip"),
      files_to_add(output),
      compress: [
        ~c".md",
        ~c".jpg",
        ~c".png"
      ]
    )
  end

  ## Helpers

  defp default_assets(config) do
    [
      {Assets.dist(config.proglang), "MD/dist"},
      {Assets.metainfo(), "META-INF"}
    ]
  end

  defp files_to_add(path) do
    Enum.reduce(Path.wildcard(Path.join(path, "**/*")), [], fn file, acc ->
      case File.read(file) do
        {:ok, bin} ->
          [{file |> Path.relative_to(path) |> String.to_charlist(), bin} | acc]

        {:error, _} ->
          acc
      end
    end)
  end

  defp generate_module_page(module_node, config) do
    content = Templates.module_page(config, module_node)
    File.write("#{config.output}/MD/#{module_node.id}.md", content)
  end

end
