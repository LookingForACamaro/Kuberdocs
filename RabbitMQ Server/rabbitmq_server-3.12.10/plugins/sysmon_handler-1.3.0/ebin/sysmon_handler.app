{application,sysmon_handler,
             [{description,"Rate-limiting system_monitor event handler"},
              {vsn,"1.3.0"},
              {licenses,["ASL2","MPL2"]},
              {links,[{"GitHub",
                       "https://github.com/rabbitmq/sysmon-handler"}]},
              {modules, ['sysmon_handler_app','sysmon_handler_example_handler','sysmon_handler_filter','sysmon_handler_sup','sysmon_handler_testhandler']},
              {registered,[sysmon_handler_sup,sysmon_handler_filter]},
              {applications,[kernel,stdlib,sasl]},
              {mod,{sysmon_handler_app,[]}},
              {env,[]}]}.
