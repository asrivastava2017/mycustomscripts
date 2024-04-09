import array

#arr = array.array('i', [1,2,3])
arr = [1,2,3]

arr.append(4);
print(arr)
#[1, 2, 3, 4]

arr.insert(2,7)
print(arr)
#[1, 2, 7, 3, 4]

arr.pop(2)
print(arr)
#[1, 2, 3, 4]

arr.remove(1)
print(arr)
#[2, 3, 4] first occurence of 1 is removed

print(arr.index(3))
#1 - position of first occurence of 3 is returned

arr.reverse()
print(arr)
#[4, 3, 2]

