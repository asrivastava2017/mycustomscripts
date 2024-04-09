import sys

def give3largestelements(arr):
    arr_size = len(arr)

    if arr_size < 3:
        print("Invalid Input")
        return 0
    
    fourth = third = second = first = -sys.maxsize

    for i in range(0,arr_size):

        if (arr[i] > first):
            fourth = third
            third = second
            second = first
            first = arr[i]

        elif (arr[i] > second):
            fourth = third
            third = second
            second = arr[i]

        elif (arr[i] > third):
            fourth = third
            third = arr[i]

        elif (arr[i] > fourth):
            fourth = arr[i]

    print("Largest 3 elements : ",first, second, third, fourth)

arrip = [1,4,19,100,3,3.5,2,4,9,19.7,8,16]
give3largestelements(arrip)