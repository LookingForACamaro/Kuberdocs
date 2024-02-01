{application, 'rabbitmq_xml_validator', [
	{description, "RabbitMQ XML validator plugin"},
	{vsn, "1.0.0"},
	{modules, ['rabbit_xml_interceptor']},
	{registered, []},
	{applications, [kernel,stdlib,rabbit_common,rabbit]},
	{optional_applications, []},
	{env, []},
		{broker_version_requirements, []}
]}.
