import Foundation
import SwiftData

/// Version 1 of the on-disk schema. When models change, add `FormaSchemaV2`
/// alongside this one and a `MigrationStage` to `FormaMigrationPlan`, rather than
/// editing V1 in place.
enum FormaSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            WeightEntry.self,
            TargetRecord.self,
            Food.self,
            FoodEntry.self,
            SavedMeal.self,
            SavedMealItem.self,
            Exercise.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            WorkoutSession.self,
            SessionExercise.self,
            WorkoutSet.self,
            ManualStepEntry.self,
            Routine.self,
            RoutineCompletion.self,
            WeeklyReviewNote.self
        ]
    }
}

enum FormaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FormaSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum Persistence {
    /// Creates the app's store. Data stays on this device: CloudKit sync is
    /// explicitly disabled so that values imported from Apple Health are never
    /// copied to iCloud.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: FormaSchemaV1.self)
        let configuration = ModelConfiguration(
            "Forma",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: FormaMigrationPlan.self, configurations: [configuration])
    }
}
