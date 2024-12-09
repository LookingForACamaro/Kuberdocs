{application, 'rabbitmq_jms_topic_exchange', [
	{description, "RabbitMQ JMS topic selector exchange plugin"},
	{vsn, "3.12.10"},
	{id, "v3.12.10"},
	{modules, ['rabbit_db_jms_exchange','rabbit_jms_topic_exchange','sjx_evaluator']},
	{registered, []},
	{applications, [kernel,stdlib,mnesia,rabbit_common,rabbit]},
	{optional_applications, []},
	{env, []}
]}.