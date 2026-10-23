%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "priv/repo/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      color: true,
      checks: %{
        disabled: [
          # Phoenix-компоненты и тестовые хелперы часто используют полные имена модулей
          {Credo.Check.Design.AliasUsage, []}
        ]
      }
    }
  ]
}
