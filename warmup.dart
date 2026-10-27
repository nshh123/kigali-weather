// Warm-up: waiting without freezing with Future, async, and await

Future<String> orderBrochette() async {
  await Future.delayed(const Duration(seconds: 3));
  return 'Your brochette is ready';
}

Future<String> orderDrink() async {
  await Future.delayed(const Duration(seconds: 1));
  return 'Your Fanta is ready';
}

void main() async {
  print('1. You order a brochette and a drink');
  final brochetteOrder = orderBrochette();
  final drinkOrder = orderDrink();

  print('2. While they are prepared, you chat with your friends');
  final drink = await drinkOrder;
  print('3. $drink');

  final food = await brochetteOrder;
  print('4. $food');
  print('5. You eat and drink!');
}
