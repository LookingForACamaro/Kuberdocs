{application, 'rabbitmq_stream_common', [
	{description, "RabbitMQ Stream Common"},
	{vsn, "3.12.10"},
	{id, "v3.12.10"},
	{modules, ['rabbit_stream_core']},
	{registered, []},
	{applications, [kernel,stdlib]},
	{optional_applications, []},
	{env, [
]}
]}.