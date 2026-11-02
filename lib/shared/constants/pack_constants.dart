/// Maximum number of meal spoons (units) in a single pack.
/// Shared between client validation and server validation (delivery_settings
/// table, key 'pack_meal_capacity'). A client bug must not be able to
/// submit a pack that exceeds this.
const int kPackMealCapacity = 8;
