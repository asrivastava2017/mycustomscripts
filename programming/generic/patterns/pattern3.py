'''
54321
5432
543
54
5
'''

def patternone(n):
    for i in range(1,n+1):
        # Print leading spaces
        for j in range(n,i-1,-1):
            print(j, end="")
        print()

patternone(5)