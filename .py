import random
import time

dados = [random.randint(1, 10000) for _ in range(10000)]

inicio = time.perf_counter()
bubble_sort(dados.copy())
print("Bubble:", time.perf_counter() - inicio)

inicio = time.perf_counter()
sorted(dados)
print("sorted:", time.perf_counter() - inicio)
