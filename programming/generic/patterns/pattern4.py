'''
55555
4444
333
22
1
In this code, the print_pattern function takes an argument n representing the number of rows in the pattern. 
The outer for loop iterates over the range from n down to 1 with a step of -1. For each iteration, the current 
value of i is converted to a string using the str function, and then multiplied by itself using the * operator
to create a string of i characters. This string is then printed using the print function.

'''
def print_pattern(n):
    for i in range(n, 0, -1):
        print(str(i) * i)

print_pattern(5)