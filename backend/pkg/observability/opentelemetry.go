package observability

import (
	"context"
	"log"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/jaeger"
	"go.opentelemetry.io/otel/sdk/resource"
	tracesdk "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
	"go.uber.org/fx"
)

func InitTracer() *tracesdk.TracerProvider {
	// Send traces to Jaeger
	exp, err := jaeger.New(jaeger.WithCollectorEndpoint(jaeger.WithEndpoint("http://localhost:14268/api/traces")))
	if err != nil {
		log.Printf("Failed to create Jaeger exporter: %v", err)
		return nil
	}

	tp := tracesdk.NewTracerProvider(
		tracesdk.WithBatcher(exp),
		tracesdk.WithResource(resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceNameKey.String("golden_p_backend"),
			semconv.DeploymentEnvironmentKey.String("production"),
		)),
	)

	otel.SetTracerProvider(tp)
	return tp
}

func RegisterTracerShutdown(lc fx.Lifecycle, tp *tracesdk.TracerProvider) {
	lc.Append(fx.Hook{
		OnStop: func(ctx context.Context) error {
			if tp != nil {
				return tp.Shutdown(ctx)
			}
			return nil
		},
	})
}

var ObservabilityModule = fx.Options(
	fx.Provide(InitTracer),
	fx.Invoke(RegisterTracerShutdown),
)
