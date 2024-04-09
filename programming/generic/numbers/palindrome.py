n=int(input("Enter number:"))
temp=n
rev=0
while(n>0):
    dig=n%10
    rev=rev*10+dig
    n=n//10
if(temp==rev):
    print("The number is a palindrome!")
else:
    print("The number isn't a palindrome!")


'''
Using slicing techinique

def is_palindrome(n):
    # Convert the number to a string
    num_str = str(n)
 
    # Use slicing to reverse the string
    reversed_str = num_str[::-1]
 
    # Compare the original string with the reversed string
    return num_str == reversed_str
 
n = int(input("Enter a number:"))
 
if is_palindrome(n):
    print("The number is a palindrome!")
else:
    print("The number is not a palindrome.")

'''