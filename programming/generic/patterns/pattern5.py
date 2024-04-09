'''
    1
   121
  12321
 1234321
123454321
'''

def print_pattern(n):
    for i in range(1,n+1):
        
        for j in range(n+1,i,-1):
            print(" ", end="")
        
        for k in range(1,i+1):
            print(k, end="")

        for l in range(i-1,0,-1):
            print(l, end="")

        print()


print_pattern(5)