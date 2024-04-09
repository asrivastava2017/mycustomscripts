'''
1
12
123
1234
12345
'''

def patternone(n):
    for i in range(1, n + 1):
        # Print leading spaces
        for j in range(1,i+1):
            print(j, end="")
        print()

patternone(5)