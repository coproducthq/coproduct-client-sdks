/// The Coproduct Flutter SDK
library;

export 'src/attribute_value.dart' show AttributeValue;
export 'src/config.dart' show CoproductConfig;
export 'src/provider_state.dart' show ProviderState;
export 'src/flag_observation.dart' show FlagObservation;
export 'src/coproduct_flag_builder.dart' show CoproductFlagBuilder;
export 'src/coproduct_scope.dart' show CoproductScope;
export 'src/errors.dart'
    show
        CoproductException,
        InvalidTargetingKey,
        MissingSdkKey,
        InvalidKeyType,
        MalformedSdkKey,
        InvalidConfig,
        UnsupportedSchemaVersion,
        CoproductAlreadyInitialized,
        CoproductInitializationCancelled;
export 'src/coproduct_client.dart' show CoproductClient, Coproduct;
