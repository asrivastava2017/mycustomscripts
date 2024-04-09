'''
1
21
321
4321
54321
'''

def patternone(n):
    for i in range(1, n + 1):
        # Print leading spaces
        for j in range(i,0,-1):
            print(j, end="")
        print()

patternone(5)