import bisect

def print_array(array, file = None):
    for x in array:
        if x["instid"] == -1:
            print("[{}]: {}".format(x["module"], x["msg"]))
            if file is not None:
                file.write("[{}]: {}".format(x["module"], x["msg"]))
        else:
            print("[{} {}]: {}".format(x["module"], x["instid"], x["msg"]))
            if file is not None:
                file.write("[{} {}]: {}".format(x["module"], x["instid"], x["msg"]))


def main():
    file = input("input file? ")
    if file == "":
        file = "./build/vitis_hls.log"
    
    f = open(file, "r")

    file_out = input("output file? ")

    for line in f:
        if "Generating csim.exe" in line: # start actual log
            break
    
    # data structure to store output
    # module, instid, msg, payload
    output = []
    # to store available modules and corresponding INSTIDs
    output_type = {}

    # parse file
    for line in f:
        if line[0] != "[":
            continue    # ignore unformatted log for now

        line = line[1:] # pop front
        index = 0

        # find module name
        for i, c in enumerate(line):
            if c.isdigit() or c == "]":
                index = i
                break
        module = line[:index] if line[index] == "]" else line[:index-1]
        line = line[index:]

        # find instid
        instid = 0
        if line[0] == "]":
            instid = -1  # no instid
        else:
            for i, c in enumerate(line):
                if not c.isdigit():
                    index = i
                    break
            instid = int(line[:index])
        
        # get msg
        for i in range(len(line) - 3):
            if line[i:i+3] == "]: ":
                index = i+2
        msg = line[index:]

        if module not in output_type:
            # add new type in list
            output_type[module] = [instid] if instid != -1 else []
        else:
            # add instid if necessary
            if instid != -1 and instid not in output_type[module]:
                bisect.insort(output_type[module], instid)

        output.append({"module": module, "instid": instid, "msg": msg})

    f.close()

    # choose modules
    output_array = output.copy()
    for x in output_type:
        while True:
            rsp = input("{}? (Y/y/N/n) ".format(x))
            if rsp in ["Y","y","yes","Yes"]:
                break
            elif rsp in ["N","n","no","No"]:
                output_array = [y for y in output_array if y["module"] != x]
                break

    # print output into log
    print("Finish parsing, printing output to log")
    if file_out != "":
        f = open(file_out,"w")
    else:
        f = None

    by_type = False
    while True:
        rsp = input("Print by module? (Y/y/N/n) ")
        if rsp in ["Y","y","yes","Yes"]:
            by_type = True
            break
        elif rsp in ["N","n","no","No"]:
            by_type = False
            break
        

    if by_type:
        for type in output_type:
            tmp_array = [y for y in output_array if y["module"] == type]
            print_array(tmp_array,f)
    else:
        print_array(output_array,f)

if __name__ == '__main__':
    main()