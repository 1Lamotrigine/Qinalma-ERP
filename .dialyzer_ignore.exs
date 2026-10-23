# Игнорируемые предупреждения Dialyzer.
#
# Каждая запись — предупреждение в сторонней зависимости, не в нашем коде.
# Проверять при обновлении зависимостей.
[
  # ash_authentication_phoenix: устаревший тип Ash.Resource.record/0 в контроллере.
  {"lib/ash_authentication_phoenix/controller.ex", :unknown_type}
]
